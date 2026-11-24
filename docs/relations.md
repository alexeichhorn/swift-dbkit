# Relations

## Model Relations

Models are classes whose columns `@Model` makes read-only. A relation is a `var` declared with its loaded type: `Target?` for
`@BelongsTo`, `[Target]` for `@HasMany` and `@ManyToMany`.

```swift
@Model(table: "users")
class UserModel {
    @Key @AutoIncrement var id: Int64
    var name: String
    @HasMany var todos: [TodoModel]
}

@Model(table: "todos")
class TodoModel {
    @Key @AutoIncrement var id: Int64
    var userID: Int64
    var title: String
    @BelongsTo(key: "userID") var user: UserModel?
    @ManyToMany(through: TodoTagModel.self, from: "todoID", to: "tagID") var tags: [TagModel]
}

@Model(table: "tags")
class TagModel {
    @Key @AutoIncrement var id: Int64
    var name: String
}

@Model(table: "todo_tags")
class TodoTagModel {
    @Key var todoID: Int64
    @Key var tagID: Int64
}
```

- `@BelongsTo(key:, references: "id")`: `key` is the foreign-key property on this model; the referenced property
  must be unique.
- `@HasMany`: takes its foreign key from the target's `@BelongsTo` back to this model. When the target has several
  (`author` and `reviewer` both pointing to `UserModel`), name it: `@HasMany(key: "reviewerID", references: "id")`,
  where `key` is the foreign-key property on the target.
- `@ManyToMany(through:, from:, to:)`: `from`/`to` are the join model's properties referencing this model's and the
  target's `id`.

Key types must match across the relation (an `Int64?` foreign key may reference an `Int64` key), or the generated
code doesn't compile. Keys can be `Int16`, `Int32`, `Int64`, `Int`, `String` or `UUID`.

## Loaded Rows Are Still Plain Models

`.with(_:)` returns rows of the generated subclass `TodoModel.Loaded<…>`, generic over each relation's state
(`NotLoaded`, `UserModel?`, `[TagModel]`, …). A loaded row is a `TodoModel`, so functions that only need columns
take the plain model, and functions that need a relation take its `With…` type:

```swift
func notify(_ todo: TodoModel) { … }                        // any todo row
func ownerName(of todo: TodoModel.WithUser) -> String? {    // rows loaded with .with(\.user), whatever else
    notify(todo)                                            // ✅ still a TodoModel
    return todo.user?.name
}
func summary(_ todo: TodoModel.WithUserAndTags) { … }       // both relations loaded

let todo = try await TodoModel.query().with(\.user).with(\.tags).first(on: db)!
notify(todo)
_ = ownerName(of: todo)
summary(todo)
```

`@Model` generates `With<Relation>` for every relation and `With<A>And<B>…` for every combination when the model
has up to four relations. They are existentials (`any …`); write `some` in a hot path to avoid the box.

Reading a relation that wasn't loaded doesn't compile: `'user' is unavailable: relation 'user' is not loaded; add
.with(\.user) to the query`. Passing a row without the relation to a `With…` parameter doesn't compile either,
though Swift's message there is less specific.

## Eager Loading And Join Filtering

`.with(_:)` takes a key path to a relation and changes the row type:

```swift
let users: [UserModel.Loaded<[TodoModel]>] = try await UserModel.query().with(\.todos).all(on: db)
let joined = try await UserModel.query().with(\.todos, .joined).all(on: db)

let todos: [TodoModel.Loaded<UserModel?, [TagModel]>] = try await TodoModel.query()
    .with(\.user, .joined)
    .with(\.tags)
    .all(on: db)

// Join to filter only; todos stay unloaded.
let filtered: [UserModel] = try await UserModel.query()
    .join(\.todos)
    .filter(TodoModel.title == "Keep me")
    .distinct()
    .all(on: db)
```

## Relation Column Paths

A belongs-to relation exposes its target's columns: `TodoModel.Relations.user.name`. Using one adds a `LEFT JOIN`
automatically; `.with(...)` still decides what's loaded.

```swift
let samsTodos = try await TodoModel.query()
    .filter(TodoModel.Relations.user.name == "Sam")
    .orderBy(TodoModel.Relations.user.name.asc)
    .with(\.user, .joined)
    .all(on: db)
```

Paths work in filters, ordering, projections, grouping and `having`, and can walk several belongs-to relations,
including self-references (`MemberModel.Relations.manager.organization.name`). Repeated uses of a path share one join, which
also serves a `.joined` load or an explicit `.join(...)` of the same relation. A self-referencing join gets an alias
like `"members.manager"`.

Path columns are nullable (`Expr<String?>` for a `String` column) because the outer join can find no row, so
`TodoModel.Relations.user.id.isNull` finds todos without a user. Paths are read-only and only supported in `SELECT` queries;
to-many relations aren't paths (use `.join(...)` or `whereExists(...)`).

## Nested Eager Loading

The closure receives the relation and loads relations of its rows; children keep their exact loaded type:

```swift
let users = try await UserModel.query()
    .with(\.todos) { $0.with(\.tags) }
    .all(on: db)

for user in users {
    for todo in user.todos {          // TodoModel.Loaded<NotLoaded, [TagModel]>
        for tag in todo.tags {
            print("\(user.name) / \(todo.title) / \(tag.name)")
        }
    }
}

// Several nested relations on the same child:
let full = try await UserModel.query()
    .with(\.todos) { $0.with(\.user, .joined).with(\.tags) }
    .all(on: db)
```

`With…` types match only the plain relation type (`UserModel.WithTodos` means `[TodoModel]`), so pass nested
results as their concrete `Loaded` type or read the children before passing them on.

## Select-In vs Joined

- `.selectIn` (default): one extra query per relation (`WHERE key = ANY($1)`), batched per level. Best with
  `limit`/`offset` and large fan-out.
- `.joined`: a `LEFT JOIN` in the main query, decoded into the tree. One query, but rows multiply per to-many
  child, and `limit` applies to the joined rows. Filters on the joined table (`TodoModel.title == "foo"`) also
  limit the loaded children.

Strategies mix freely: a joined relation can have select-in children and the other way round.

## Explicit Load Afterwards

Relations never load on access. Load them explicitly with one select-in query, for one row or an array:

```swift
let user = try await UserModel.find(1, on: db)!
let loaded = try await user.load(\.todos, on: db)
print(loaded.todos.count)

let all = try await UserModel.query().all(on: db)
let withTags = try await all.load(\.todos, on: db) { $0.with(\.tags) }
print(withTags.count)
```

On a loaded row, `load(_:on:)` keeps the relations already loaded.

## Design: Why Models Are Classes

The goal: functions take `UserModel` for any row and `UserModel.WithTodos` when a relation must be loaded,
without converting at call sites, and reading an unloaded relation fails at compile time.

- A row with loaded relations has to be a different type than the plain row, or the compiler couldn't know what's
  loaded. Swift only converts implicitly from a subclass to its superclass or from a value to a protocol, so with
  struct models every call would need an explicit conversion (`user.model`). A generated subclass removes it.
- Columns are read-only (`@Model` turns each `var` into a getter over private storage, like `@Observable` does with
  init accessors, which keeps `var x: T = default` valid), so rows are immutable and sharing a reference behaves like
  copying a value. Change rows with `update()` or `active()`. Because the class is subclassed, `@Model` adds
  `@unchecked Sendable`; that's sound because only the generated initializer writes the storage.
- Relation properties are unavailable on the plain model. On `Loaded`, a generated protocol per relation exposes
  the loaded value under the same name; Swift prefers the available declaration, so `todo.user` compiles exactly
  when the relation is loaded.
- `With…` types are typealiases of constrained existentials such as `any _UserSlot<UserModel?>`, because a macro
  may only add conformances that its declaration lists. The relation state is therefore an associated type that
  `Loaded` always provides, rather than a conditional conformance.
- `.with(\.user)` on a plain query uses `TodoModel.Relations.user`; on a loaded query it uses
  `TodoModel.Loaded<…>.LoadedRelations.user`, which knows the other relation states and keeps them. Both live in
  nested enums: a static `TodoModel.user` would shadow the unavailable instance property and replace its "not
  loaded" message, and a subclass can't redeclare an inherited static with a different type.
