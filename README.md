# DBKit

A small, Postgres-first async ORM for Swift with typed columns, typed expressions and type-level loaded
relations.

The package is being built; its guides arrive feature by feature.

## Quick Intro

Declare models as classes with `@Model`. Columns are `var`s that `@Model` makes read-only, optionally with a default.

```swift
@Model(table: "users")
class UserModel {
    @Key @AutoIncrement var id: Int64
    var name: String
    @Unique var email: String
}

@Model(table: "todos")
class TodoModel {
    @Key @AutoIncrement var id: Int64
    @Index var userID: Int64
    var title: String
    var isComplete: Bool = false
}
```

```swift
let db = try Database(url: "postgres://app:secret@localhost:5432/app")
// Run `db` in your ServiceGroup (or a task); see docs/database.md.

let users = try await UserModel.query()
    .filter(UserModel.email.ilike("%@example.com"))
    .orderBy(UserModel.name.asc)
    .all(on: db)

for user in users {
    print("\(user.name) <\(user.email)>")
}
```

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

`@Model` generates a static typed column per property (`TodoModel.userID` is a `Column<TodoModel, Int64>`).
Column names default to the snake_case property name (`userID` → `user_id`); override with `@ColumnName("type")`.
Property names starting with `__dbkit_` are reserved for the code `@Model` generates.

Comparing a column with a value of another type doesn't compile.

## More Docs

- [Querying](docs/querying.md)
- [Database](docs/database.md)

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE) at your option.
