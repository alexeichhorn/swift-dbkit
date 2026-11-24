import Logging
import NIOCore
import PostgresNIO
import Synchronization

/// An executor that can keep one connection for as long as a cursor reads on it.
protocol CursorExecutor: DatabaseExecutor {
    func cursorConnection() async throws -> CursorConnection
}

/// The connection a ``Cursor`` reads on.
struct CursorConnection: Sendable {
    let connection: PostgresConnection
    /// A cursor needs a transaction. It opens its own, unless the executor already is one, which it leaves open.
    let ownsTransaction: Bool
    /// Hands a pooled connection back. Called once the cursor's last statement is answered.
    var release: @Sendable () -> Void = {}
}

/// A server-side cursor over one query, read in batches so PostgreSQL only produces the rows that are fetched.
///
/// Dropping the cursor before its last row ends it without reading the rest. Its last statements are queued on the
/// connection right then and never awaited, so they also run when the reading task is cancelled, and before anything
/// that task sends next.
final class Cursor {
    /// Rows fetched per round trip. Bounds what PostgreSQL produces beyond the rows that are read.
    static let batchSize = 1000

    private let target: CursorConnection
    private let logger: Logger
    /// Unique, because one connection can have several cursors open.
    private let name = "dbkit_cursor_\(cursorIDs.add(1, ordering: .relaxed).newValue)"
    private var batch: [PostgresRow] = []
    private var index = 0
    private var isLastBatch = false
    private var isFinished = false

    private init(target: CursorConnection, logger: Logger) {
        self.target = target
        self.logger = logger
    }

    static func open(_ query: PostgresQuery, on executor: any CursorExecutor) async throws -> Cursor {
        let cursor = Cursor(target: try await executor.cursorConnection(), logger: executor.logger)
        if cursor.target.ownsTransaction { try await cursor.run("BEGIN") }
        try await cursor.run(PostgresQuery(unsafeSQL: "DECLARE \(cursor.name) NO SCROLL CURSOR FOR \(query.sql)", binds: query.binds))
        return cursor
    }

    /// The next row in query order, or `nil` after the last one.
    func next() async throws -> PostgresRow? {
        guard !isFinished else { return nil }
        if index == batch.count, !isLastBatch {
            batch = try await run(PostgresQuery(unsafeSQL: "FETCH \(Self.batchSize) FROM \(name)"))
            // The wait for PostgreSQL's answer doesn't end on cancellation, like every query on a connection.
            try Task.checkCancellation()
            index = 0
            isLastBatch = batch.count < Self.batchSize
        }
        guard index < batch.count else {
            try await finish(target.ownsTransaction ? ["CLOSE \(name)", "COMMIT"] : ["CLOSE \(name)"]).get()
            return nil
        }
        defer { index += 1 }
        return batch[index]
    }

    deinit {
        finish(target.ownsTransaction ? ["ROLLBACK"] : ["CLOSE \(name)"])
    }

    @discardableResult
    private func run(_ query: PostgresQuery) async throws -> [PostgresRow] {
        do {
            return try await target.connection.rows(query, logger: logger).get()
        } catch {
            // The failed statement aborted the transaction, which closed the cursor.
            finish(target.ownsTransaction ? ["ROLLBACK"] : [])
            throw error
        }
    }

    /// Sends the cursor's last statements and gives the connection back once they are answered. Only the first call
    /// does anything.
    @discardableResult
    private func finish(_ statements: [String]) -> EventLoopFuture<Void> {
        let connection = target.connection
        guard !isFinished else { return connection.eventLoop.makeSucceededVoidFuture() }
        isFinished = true
        let sent = statements.map { connection.rows(PostgresQuery(unsafeSQL: $0), logger: logger).map { _ in } }
        let answered = EventLoopFuture.whenAllComplete(sent, on: connection.eventLoop)
        answered.whenComplete { [release = target.release] _ in release() }
        return answered.flatMapThrowing { results in
            for result in results { try result.get() }
        }
    }
}

private let cursorIDs = Atomic<UInt64>(0)
