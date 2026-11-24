import DBKit
import Testing

/// Answers no query: it throws the first query a call sends, so a test reads the SQL of `count`, `exists` or
/// `paginate` without a database.
struct FirstQueryExecutor: DatabaseExecutor {
    struct Sent: Error {
        let query: PostgresQuery
    }

    let logger = Logger(label: "first-query")

    func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        throw Sent(query: query)
    }
}

/// The SQL and the number of binds of the first query `call` sends.
func firstQuery(_ call: (FirstQueryExecutor) async throws -> Void) async throws -> (sql: String, bindCount: Int) {
    let sent = try await #require(throws: FirstQueryExecutor.Sent.self) { try await call(FirstQueryExecutor()) }
    return (sent.query.sql, sent.query.binds.count)
}

/// Runs each query on `base` and keeps its SQL, to check every query a call sends.
struct RecordingExecutor<Base: DatabaseExecutor>: DatabaseExecutor {
    let base: Base
    let log = SQLLog()

    var logger: Logger { base.logger }

    func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        await log.append(query.sql)
        return try await base.query(query)
    }
}

actor SQLLog {
    private(set) var statements: [String] = []

    func append(_ sql: String) {
        statements.append(sql)
    }
}
