import DBKit

// rust-dbkit's `fail_streaming_eager_loads.rs`. Eager loading needs every row of a level before it loads the next, so a
// query with `with(_:)` has no `stream(on:)` rather than dropping the load.

private func eagerLoads(_ db: Database, _ tx: Transaction) async throws {
    _ = try await PathRecordModel.query().with(\.owner).stream(on: db)  // error: 'stream(on:)' on 'Query' requires the types
    _ = try await PathRecordModel.query().with(\.owner, .joined).stream(on: db)  // error: 'stream(on:)' on 'Query' requires the types
    let nested = PathRecordModel.query().with(\.owner) { $0.with(\.organization, .joined) }
    _ = try await nested.stream(on: db)  // error: 'stream(on:)' on 'Query' requires the types
    _ = try await PathRecordModel.query().with(\.owner).stream(on: tx)  // error: 'stream(on:)' on 'Query' requires the types
    // Waits for slice 28: `stream(on:)` with a `DedicatedConnection` doesn't compile.
}
