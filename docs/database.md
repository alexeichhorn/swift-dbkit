# Database

## Connecting

```swift
let db = try Database(url: "postgres://app:secret@localhost:5432/app?sslmode=require", connections: 3...10)
```

`connections` is the pool size: it keeps the lower bound open and grows to the upper bound. The default is `0...20`.

`sslmode` follows libpq: `disable`, `prefer` (default), `require` (encrypted, not verified), `verify-full`
(encrypted and verified). For full control, build a `PostgresClient` yourself and pass it to
`Database(client:logger:)`.

## Running The Pool

`Database` wraps a `PostgresClient` connection pool, which only serves queries while its `run()` method runs.
`Database` is a swift-service-lifecycle `Service`, so add it to your `ServiceGroup`:

```swift
import Logging
import ServiceLifecycle

func runApp(databaseURL: String) async throws {
    let logger = Logger(label: "app")
    let db = try Database(url: databaseURL, logger: logger)
    let services = ServiceGroup(services: [db], gracefulShutdownSignals: [.sigterm], logger: logger)
    try await services.run()
}
```

Outside a service group, run it in a task: `async let pool: Void = db.run()`, cancelling the task to shut down.

## Other PostgresNIO Libraries

Libraries such as `swift-jobs-postgres` take the underlying pool, `db.client`, so they share connections with DBKit.

## Transactions

`transaction` runs the closure on one pooled connection, commits when it returns and rolls back when it throws,
rethrowing your error. Queries take the transaction as their executor:

```swift
let todoCount = try await db.transaction { tx in
    try await TodoModel.insert(TodoModel.Insert(userID: userID, title: "Ship it")).execute(on: tx)
    return try await TodoModel.query().filter(TodoModel.userID == userID).all(on: tx).count
}
```

Don't let the `Transaction` escape the closure. `tx.connection` exposes the underlying `PostgresConnection`. A query
on a transaction whose connection was lost throws `DBKitError.connectionClosed`.

## Executors

Every query method takes `some DatabaseExecutor`: a `Database` or a `Transaction`. Write helpers against the protocol
to use them with both:

```swift
func activeUsers(on executor: some DatabaseExecutor) async throws -> [UserModel] {
    try await UserModel.query().filter(UserModel.email.ilike("%@example.com")).all(on: executor)
}
```

`executor.query(_:)` runs raw SQL; see [Querying](querying.md#raw-sql).
