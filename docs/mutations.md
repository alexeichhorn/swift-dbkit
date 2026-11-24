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

Use the update builder for bulk or conditional updates. `set(_:to:)` takes a value of the column's type:

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
    .set(JobModel.attempts, to: 0)
    .filter(JobModel.state == "failed")
    .returningAll()
    .all(on: db)
```

Without a filter, `update()` changes every row.

## Delete

```swift
let user = try await UserModel.find(1, on: db)!
try await user.delete(on: db)

let removed = try await JobModel.delete().filter(JobModel.state == "done").execute(on: db)
```

`user.delete(on:)` deletes by primary key. Without a filter, `delete()` removes every row.

## Bulk Insert

```swift
let inserted = try await UserModel.insert([
    UserModel.Insert(name: "Alpha", email: "alpha@db.com"),
    UserModel.Insert(name: "Beta", email: "beta@db.com"),
]).execute(on: db)  // 2
```

An empty array sends no statement and returns 0.
