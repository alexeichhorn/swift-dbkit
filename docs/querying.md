# Querying

The examples use the `UserModel` and `TodoModel` from the [README](../README.md).

## Basic Query + Ordering

```swift
let users = UserModel.query()
    .filter(UserModel.email.ilike("%@example.com"))
    .orderBy(UserModel.name.asc)
    .limit(20)
    .offset(40)

let open = TodoModel.query()
    .filter(TodoModel.isComplete == false)
    .orderBy(TodoModel.userID.asc, TodoModel.id.desc)
    .distinct()
```

Filters combine with `AND`. Use `&&`, `||` and `!` inside one filter:

```swift
let todos = TodoModel.query()
    .filter(TodoModel.userID == 7 && (TodoModel.title.like("Buy%") || !TodoModel.isComplete))
```

Comparisons are `==`, `!=`, `<`, `<=`, `>` and `>=` against a value. Other predicates: `.in([...])`, `.notIn([...])`,
`.between(a, b)`, `.like`, `.ilike`. `in` with an empty array matches nothing, `notIn` with an empty array matches
everything.

Any query can show its SQL without a database: `render()` returns the SQL and binds.

```swift
let rendered = todos.render()
// SELECT "todos".* FROM "todos" WHERE ("todos"."user_id" = $1 AND ("todos"."title" LIKE $2 OR NOT ("todos"."is_complete")))
// rendered.binds: 7, "Buy%"
```
