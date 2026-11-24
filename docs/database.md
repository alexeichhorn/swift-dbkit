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

## Migrations

Migrations are plain SQL files named `<version>_<name>.sql`, applied in version order:

```text
Migrations/
  0001_create_users.sql
  0002_add_todos.sql
```

```swift
// Package.swift: resources: [.copy("Migrations")]
try await db.migrate(Bundle.module.url(forResource: "Migrations", withExtension: nil)!)
```

- Versions compare as numbers, so `10_…` runs after `9_…`. Each file needs a version of its own.
- Each pending file runs in its own transaction and is recorded in `_dbkit_migrations` with a checksum.
- Migrations are forward-only. A run fails when an applied file was edited or deleted; fix mistakes with a new file.
- An advisory lock lets several replicas run `migrate` at startup; the first applies, the others wait and skip.
- A file may hold several statements. They're split at top-level semicolons; semicolons in quotes, escape strings
  (`E'…'`), `$$` function bodies and comments are fine.
- A failed migration throws `DBKitError.migrationFailed` with the file name and the PostgreSQL error. The failing file
  leaves nothing behind, and the files before it stay applied.

Keep the tables in sync with your `@Model` types; DBKit doesn't create or check them.

## Other PostgresNIO Libraries

Libraries such as `swift-jobs-postgres` take the underlying pool, `db.client`, so they share connections with DBKit.

## Transactions

`transaction` runs the closure on one pooled connection, commits when it returns and rolls back when it throws,
rethrowing your error. Queries take the transaction as their executor:

```swift
let renamed = try await db.transaction { tx in
    let user = try await UserModel.query().filter(UserModel.id == 1).forUpdate().first(on: tx)
    var active = user!.active()
    active.name = "Renamed"
    return try await active.update(on: tx)
}
```

Don't let the `Transaction` escape the closure. `tx.connection` exposes the underlying `PostgresConnection`. A query
on a transaction whose connection was lost throws `DBKitError.connectionClosed`.

## Transaction-Local Postgres Settings

```swift
let users = try await db.transaction { tx in
    try await tx.setLocal("statement_timeout", "5s")
    return try await UserModel.query().filter(UserModel.email.like("%@example.com")).all(on: tx)
}
```

`setLocal` uses `set_config(name, value, true)`, so the setting ends with the transaction instead of leaking to
the next user of the pooled connection.

## Dedicated Connections

A dedicated connection is opened with the pool's URL and TLS settings but isn't part of the pool. It lives until
you close it, so it can hold session state that must not leak back into a pool:

```swift
let connection = try await db.dedicatedConnection()
let users = try await UserModel.query().all(on: connection)
await connection.close()
```

Closing releases its advisory locks and ends its notification sequences. `connection.ping()` throws once the
connection is lost, and its locks with it; queries on a lost connection throw `DBKitError.connectionClosed`. A
`Database(client:logger:)` has no URL, so its `dedicatedConnection()` throws `DBKitError.missingDatabaseURL`.

## Advisory Locks

Session advisory locks by name, to make sure only one process does a piece of work:

```swift
let lock = AdvisoryLock("import:\(importID)")
if try await lock.tryAcquire(on: connection) {
    try await runImport(importID)
    try await lock.release(on: connection)
}
```

`tryAcquire` never waits: it returns `false` when another session holds the lock. The lock stays with the
connection until `release` or `close()`; taking it twice needs two releases. PostgreSQL derives the lock key
from the name with `hashtextextended(name, 0)`.

## LISTEN / NOTIFY

`notify` runs on any executor; in a transaction the notification is delivered on commit. Listening needs a
dedicated connection:

```swift
try await db.notify("imports", payload: "\(importID)")

try await connection.listen(on: "imports") { notifications in
    for try await notification in notifications {
        print(notification.payload)
    }
}
```

Listening stops when the closure returns. Notifications sent while nobody listens are lost. The sequence throws when
the connection drops; open a new dedicated connection and listen again.

## Executors

Every query method takes `some DatabaseExecutor`: a `Database`, a `Transaction` or a `DedicatedConnection`. Only
`stream(on:)` is narrower and takes a `Database` or a `Transaction`. Write helpers against the protocol to use them
with all three:

```swift
func activeUsers(on executor: some DatabaseExecutor) async throws -> [UserModel] {
    try await UserModel.query().filter(UserModel.email.ilike("%@example.com")).all(on: executor)
}
```

`executor.query(_:)` runs raw SQL; see [Querying](querying.md#raw-sql).
