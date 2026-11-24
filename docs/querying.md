# Querying

The examples use the `UserModel` and `TodoModel` from the [README](../README.md) plus the models declared below.

## Basic Query + Ordering

```swift
let users = try await UserModel.query()
    .filter(UserModel.email.ilike("%@example.com"))
    .orderBy(UserModel.name.asc)
    .limit(20)
    .offset(40)
    .all(on: db)

let open = try await TodoModel.query()
    .filter(TodoModel.isComplete == false)
    .orderBy(TodoModel.userID.asc, TodoModel.id.desc)
    .distinct()
    .all(on: db)

let todo = try await TodoModel.find(1, on: db)
let firstOpen = try await TodoModel.query().filter(TodoModel.isComplete == false).orderBy(TodoModel.id.desc).first(on: db)
```

`find` exists on models with a single `@Key`. `first` adds `LIMIT 1`.

Filters combine with `AND`. Use `&&`, `||` and `!` inside one filter:

```swift
let todos = TodoModel.query()
    .filter(TodoModel.userID == 7 && (TodoModel.title.like("Buy%") || !TodoModel.isComplete))
let rows = try await todos.all(on: db)
```

Comparisons are `==`, `!=`, `<`, `<=`, `>` and `>=` against a value or [another
expression](#column-to-column-comparisons). Other predicates: `.in([...])`, `.notIn([...])`, `.between(a, b)` with values or expressions as bounds,
`.isNull`, `.isNotNull`, `.like`, `.ilike`, `.isDistinct(from:)`, `.isNotDistinct(from:)`. `in` with an empty array
matches nothing, `notIn` with an empty array matches everything. On a nullable column a predicate is `Expr<Bool?>` and
takes optional values; see [Nullability](expressions.md#nullability).

Any query can show its SQL without a database: `render()` returns the SQL and binds.

```swift
let rendered = todos.render()
// SELECT "todos".* FROM "todos" WHERE ("todos"."user_id" = $1 AND ("todos"."title" LIKE $2 OR NOT ("todos"."is_complete")))
// rendered.binds: 7, "Buy%"
```

## Row-Value Filters

```swift
@Model(table: "lookup_rows")
class LookupRowModel {
    @Key @AutoIncrement var id: Int64
    var scope: String
    var externalKey: String
    var locale: String?
}
```

```swift
let rows = try await LookupRowModel.query()
    .filter(
        SQL.row(LookupRowModel.scope, LookupRowModel.externalKey, LookupRowModel.locale).in([
            ("public", "alpha", "en"),
            ("internal", "beta", nil),
        ])
    )
    .all(on: db)
```

`SQL.row` takes two to six columns. Each tuple value has its column's type, so a wrong type or tuple length doesn't
compile, an integer literal takes its column's integer type, and a nullable column takes an optional or `nil`, rendered
`NULL`. `in` is `Expr<Bool?>` when a column is nullable and `Expr<Bool>` otherwise. A row containing NULL never
matches, since PostgreSQL compares it as NULL: the `("internal", "beta", nil)` row above matches nothing. `in` with an
empty array matches nothing.

## Dynamic Conditions

```swift
func users(region: String?, name: String?, on db: Database) async throws -> [UserModel] {
    var condition = Condition.all
    if let region { condition.add(UserModel.email.ilike("%.\(region)")) }
    if let name { condition.add(UserModel.name == name) }
    return try await UserModel.query().filter(condition).all(on: db)
}
```

`Condition.any` combines with `OR`. `add` takes required and nullable predicates. An empty condition adds no filter:
its `isEmpty` is `true` and its `predicate` is `nil`. Otherwise `predicate` is an `Expr<Bool?>`, even when every added
predicate is required. Updates and deletes filter by the unwrapped predicate, and a condition nests in another the same
way:

```swift
var owners = Condition.any
owners.add(TodoModel.userID == 1)
owners.add(TodoModel.userID == 2)

var condition = Condition.all
condition.add(TodoModel.isComplete == true)
if let owned = owners.predicate { condition.add(owned) }

if let predicate = condition.predicate {
    try await TodoModel.delete().filter(predicate).execute(on: db)
}
```

## Column-To-Column Comparisons

Comparison operators accept a value or another expression of the same type on either nullability:

```swift
@Model(table: "jobs")
class JobModel {
    @Key @AutoIncrement var id: Int64
    var contentHash: String
    var embeddingHash: String?
    var retryCount: Int32
    var maxRetries: Int32
}
```

```swift
let changed = try await JobModel.query().filter(JobModel.embeddingHash != JobModel.contentHash).all(on: db)
let retryable = try await JobModel.query().filter(JobModel.retryCount < JobModel.maxRetries).all(on: db)

// NULL-safe mismatch with PostgreSQL's IS DISTINCT FROM:
let stale = try await JobModel.query().filter(JobModel.embeddingHash.isDistinct(from: JobModel.contentHash)).all(on: db)
// Or with a fallback for NULL:
let staleOrMissing = try await JobModel.query().filter((JobModel.embeddingHash ?? "") != JobModel.contentHash).all(on: db)
```

A comparison is `Expr<Bool?>` when either side is nullable, so `changed` skips rows without an embedding hash.
`isDistinct(from:)` and `isNotDistinct(from:)` treat NULL as a value and are always `Expr<Bool>`; they also take a
value or `nil`. A comparison used as an operand of another comparison is put in parentheses:
`TodoModel.isComplete == (TodoModel.userID > 1)` renders `"todos"."is_complete" = ("todos"."user_id" > $1)`.

## Raw SQL

Interpolated values in a `PostgresQuery` become bind parameters. Decode rows as typed tuples or as a model:

```swift
let userID: Int64 = 7
for try await (id, title) in try await db.query("SELECT id, title FROM todos WHERE user_id = \(userID)").decode((Int64, String).self) {
    print(id, title)
}

let todos = try await db.query("SELECT * FROM todos WHERE title ILIKE \("%milk%")", as: TodoModel.self)
```

A model is decoded by column name, so the query must select all of its columns. A missing column throws
`DBKitError.missingColumn`, a value of the wrong type or an unexpected NULL throws `DBKitError.decodingFailed`, both
naming the column.
