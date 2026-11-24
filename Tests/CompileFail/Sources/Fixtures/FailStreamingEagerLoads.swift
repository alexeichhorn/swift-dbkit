import DBKit

// rust-dbkit's `fail_streaming_eager_loads.rs`. Eager loading needs every row of a level before it loads the next, so a
// query with `with(_:)` has no `stream(on:)` rather than dropping the load.

private func eagerLoads(_ db: Database, _ tx: Transaction, _ connection: DedicatedConnection) async throws {
    _ = try await PathRecordModel.query().with(\.owner).stream(on: db)  // error: 'stream(on:)' on 'Query' requires the types
    _ = try await PathRecordModel.query().with(\.owner, .joined).stream(on: db)  // error: 'stream(on:)' on 'Query' requires the types
    let nested = PathRecordModel.query().with(\.owner) { $0.with(\.organization, .joined) }
    _ = try await nested.stream(on: db)  // error: 'stream(on:)' on 'Query' requires the types
    _ = try await PathRecordModel.query().with(\.owner).stream(on: tx)  // error: 'stream(on:)' on 'Query' requires the types
    // `stream(on:)` takes a `Database` or a `Transaction`, not a dedicated connection.
    _ = try await PathRecordModel.query().stream(on: connection)  // error: no exact matches in call to instance method 'stream'
}
