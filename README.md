# DBKit

A small, Postgres-first async ORM for Swift with typed columns, typed expressions and type-level loaded
relations. It's the Swift port of [rust-dbkit](https://github.com/alexeichhorn/rust-dbkit), built on PostgresNIO and
framework-independent.

## Usage

```swift
.package(url: "https://github.com/alexeichhorn/swift-dbkit.git", branch: "main"),
// target dependency:
.product(name: "DBKit", package: "swift-dbkit"),
```

```swift
import DBKit
```

`import DBKit` also re-exports PostgresNIO for raw SQL and `PostgresClient`.

## Quick Intro

Declare models as classes with `@Model`. Columns are `var`s that `@Model` makes read-only, optionally with a default;
relations are `var`s of their loaded type.

```swift
@Model(table: "users")
class UserModel {
    @Key @AutoIncrement var id: Int64
    var name: String
    @Unique var email: String
    @HasMany var todos: [TodoModel]
}

@Model(table: "todos")
class TodoModel {
    @Key @AutoIncrement var id: Int64
    @Index var userID: Int64
    var title: String
    var isComplete: Bool = false
    @BelongsTo(key: "userID") var user: UserModel?
}
```

```swift
let db = try Database(url: "postgres://app:secret@localhost:5432/app")
// Run `db` in your ServiceGroup (or a task); see docs/database.md.

let users = try await UserModel.query()
    .filter(UserModel.email.ilike("%@example.com"))
    .orderBy(UserModel.name.asc)
    .with(\.todos)
    .all(on: db)

for user in users {
    for todo in user.todos {
        print("\(user.name) / \(todo.title)")
    }
}
```

The loaded graph is part of the type, and loaded rows are still plain models:

```swift
func sendDigest(to user: UserModel) { … }                  // any user row
func sendTodoList(to user: UserModel.WithTodos) { … }      // only users loaded with .with(\.todos)

sendDigest(to: user)       // ✅ also a loaded user
sendTodoList(to: user)     // ✅ only compiles after .with(\.todos)
```

Reading `user.todos` without `.with(\.todos)` doesn't compile: "relation 'todos' is not loaded; add
.with(\.todos) to the query".

Without a database, `render()` shows a query's SQL and binds:

```swift
let rendered = UserModel.query()
    .filter(UserModel.email.ilike("%@example.com"))
    .orderBy(UserModel.name.asc)
    .render()

print(rendered.sql)
// SELECT "users".* FROM "users" WHERE "users"."email" ILIKE $1 ORDER BY "users"."name" ASC
print(rendered.binds.map(\.description))
// ["%@example.com"]
```

`@Model` generates a static typed column per property (`TodoModel.userID` is a `Column<TodoModel, Int64>`)
and one entry per relation in `TodoModel.Relations` (`TodoModel.Relations.user.name` is a relation path for filters).
Column names default to the snake_case property name (`userID` → `user_id`); override with `@ColumnName("type")`.
Property names starting with `__dbkit_` are reserved for the code `@Model` generates. A table in a PostgreSQL schema
takes `@Model(table: "users", schema: "app")`; see [Tables In Other Schemas](docs/querying.md#tables-in-other-schemas).

Required and nullable columns stay distinct: `nil` and optional values are accepted only where the property is
optional, and a comparison is nullable when an operand is (`Expr<Bool?>` instead of `Expr<Bool>`). Comparing a column
with a value or column of another type doesn't compile.

## Common Mutations

Insert with the generated `Insert` type. Auto-increment keys and relations are left out; columns with a Swift default
(`var isComplete: Bool = false`, `var id: UUID = UUID()`) and optional columns can be omitted. Defaults are evaluated
per insert:

```swift
let created = try await UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com"))
    .returningAll()
    .first(on: db)
```

Update one loaded row with `active()`; only the columns you set are written:

```swift
var active = user.active()
active.name = "Renamed"
let updated = try await active.update(on: db)
```

Delete a loaded row by primary key:

```swift
try await user.delete(on: db)
```

Use the `update()` / `delete()` builders for bulk or conditional mutations.

A violated unique constraint surfaces as a `PSQLError` that names it:

```swift
do {
    try await UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com")).execute(on: db)
} catch let error as PSQLError where error.isUniqueViolation(of: "users_email_key") {
    // the email is taken
}
```

## Postgres Enums

`@DatabaseEnum` stores a plain enum as a PostgreSQL enum type. Each label is the snake_case case name:

```swift
@DatabaseEnum("task_state")
enum TaskState { case pendingReview, inProgress, completed }   // pending_review, in_progress, completed
```

## Connections

The pool size is a range: it keeps the lower bound open and grows to the upper bound.

```swift
let db = try Database(url: "postgres://app:secret@localhost:5432/app", connections: 3...10)
```

A dedicated connection lives outside the pool until you close it. It holds the session state that must not leak back
into a pool: advisory locks and `LISTEN`.

```swift
let connection = try await db.dedicatedConnection()

let lock = AdvisoryLock("import:\(importID)")
if try await lock.tryAcquire(on: connection) {   // never waits
    …
    try await lock.release(on: connection)
}

try await db.notify("imports", payload: "\(importID)")           // on any executor
try await connection.listen(on: "imports") { notifications in
    for try await notification in notifications {
        print(notification.payload)
    }
}

await connection.close()
```

## More Docs

- [Querying](docs/querying.md)
- [Mutations](docs/mutations.md)
- [Relations](docs/relations.md) (including why models are classes)
- [Expressions and aggregation](docs/expressions.md)
- [PostgreSQL string functions](docs/string-functions.md)
- [Postgres types](docs/postgres-types.md)
- [Database](docs/database.md)

## Differences From rust-dbkit

Swift idioms replace Rust's: operators (`==`, `&&`, `??`) instead of `eq` / `and` / `unwrap_or`, key paths for
relations (`.with(\.todos)`), and models as classes. [Parity with rust-dbkit](docs/rust-parity.md) lists every other
difference, what is left out and why.

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE) at your option.
