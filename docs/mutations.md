# Mutations

The examples use the `UserModel` from the [README](../README.md) plus the models declared below.

## Insert

`@Model` generates a nested `Insert` type with every column except `@AutoIncrement` keys. Required fields stay
required; optional fields default to `nil`, and a column's Swift default (`var isActive: Bool = true`) becomes the
field's default, evaluated per insert:

```swift
let created = try await UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com"))
    .returningAll()
    .first(on: db)

let inserted = try await UserModel.insert(UserModel.Insert(name: "Sam", email: "s@b.com")).execute(on: db)  // 1
```

`execute(on:)` returns the number of affected rows; `returningAll()` returns the rows themselves.

## Update

For one loaded row, use `active()`. It tracks the columns you assign, so the update writes only those, by
primary key:

```swift
let user = try await UserModel.find(1, on: db)!
var active = user.active()
active.name = "Renamed"
let updated = try await active.update(on: db)  // UPDATE "users" SET "name" = $1 WHERE "users"."id" = $2 RETURNING *
```

The update filters by the key the row was loaded with, so assigning a key column moves the row to the new key. With
nothing assigned, `update(on:)` sends no query and returns the row unchanged. When no row matches the key, it throws
`DBKitError.rowNotFound`.

Use the update builder for bulk or conditional updates. `set(_:to:)` takes a value of the column's type or an
expression:

```swift
@Model(table: "jobs")
class JobModel {
    @Key @AutoIncrement var id: Int64
    var state: String
    var attempts: Int32
    var error: String?
}
```

```swift
let retried = try await JobModel.update()
    .set(JobModel.state, to: "queued")
    .set(JobModel.attempts, to: JobModel.attempts + 1)
    .filter(JobModel.state == "failed")
    .returningAll()
    .all(on: db)
```

Without a filter, `update()` changes every row.

`update()` and `delete()` also accept `whereExists(_:)` / `whereNotExists(_:)` subqueries; see [Correlated EXISTS /
NOT EXISTS](querying.md#correlated-exists--not-exists).

## Delete

```swift
let user = try await UserModel.find(1, on: db)!
try await user.delete(on: db)

let removed = try await JobModel.delete().filter(JobModel.state == "done").execute(on: db)
```

`user.delete(on:)` deletes by primary key. Without a filter, `delete()` removes every row.

## Save

`save(on:)` inserts a new active model and updates a loaded one, for code that genuinely needs one path for both:

```swift
var draft = ActiveModel<UserModel>()
draft.name = "Saved"
draft.email = "saved@db.com"
let created = try await draft.save(on: db)

var active = created.active()
active.name = "Renamed"
let updated = try await active.save(on: db)
```

Reading a column you haven't set on a new `ActiveModel` is a programmer error and traps, as are `update(on:)` and
`delete(on:)` on it.

## Bulk Insert

```swift
let inserted = try await UserModel.insert([
    UserModel.Insert(name: "Alpha", email: "alpha@db.com"),
    UserModel.Insert(name: "Beta", email: "beta@db.com"),
]).execute(on: db)  // 2
```

An empty array sends no statement and returns 0.

## Insert Conflict Handling

Conflict targets and update columns must be columns of the inserted model:

```swift
@Model(table: "order_lines")
class OrderLineModel {
    @Key var orderID: Int64
    @Key var lineID: Int64
    var note: String
}
```

```swift
let ignored = try await UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com"))
    .onConflictDoNothing(UserModel.email)
    .execute(on: db)  // 0 when the email exists

let line = try await OrderLineModel.insert(OrderLineModel.Insert(orderID: 7, lineID: 8, note: "Updated via upsert"))
    .onConflict(OrderLineModel.orderID, OrderLineModel.lineID, doUpdate: OrderLineModel.note)
    .returningAll()
    .first(on: db)
```

`onConflictDoNothing()` without columns ignores any unique violation.

Both column lists of `onConflict` can also be tuples, so one list can be kept in a constant and reused:

```swift
let lineKey = (OrderLineModel.orderID, OrderLineModel.lineID)
let insert = OrderLineModel.insert(OrderLineModel.Insert(orderID: 7, lineID: 9, note: "New"))
    .onConflict(lineKey, doUpdate: OrderLineModel.note)
```
