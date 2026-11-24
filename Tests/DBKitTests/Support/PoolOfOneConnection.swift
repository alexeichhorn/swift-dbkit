import DBKit
import Testing

/// Runs `body` on a pool of its own with one connection. Every query and stream on it shares that connection, so
/// `TEMP` tables created on it stay in scope, and a stream that keeps the connection makes the next query wait.
func withPoolOfOneConnection(_ body: (Database) async throws -> Void) async throws {
    let db = try Database(url: testDatabaseURL(), connections: 0...1)
    try await withThrowingDiscardingTaskGroup { tasks in
        tasks.addTask { await db.run() }
        defer { tasks.cancelAll() }
        try await body(db)
    }
}

/// The first column of the first row, such as a count.
func integer(_ query: PostgresQuery, on executor: some DatabaseExecutor) async throws -> Int64? {
    try await executor.query(query).collect().first?.decode(Int64.self)
}

/// Checks that the next connection of `db` holds no cursor and is outside a transaction. On a pool of one connection,
/// that is the connection the last stream read on, and a stream that kept it makes this wait.
func expectNoCursorOrTransaction(on db: Database) async throws {
    #expect(try await integer("SELECT count(*) FROM pg_cursors WHERE name <> ''", on: db) == 0)
    // Outside a transaction every statement gets a transaction ID of its own.
    #expect(try await integer("SELECT txid_current()", on: db) != integer("SELECT txid_current()", on: db))
}
