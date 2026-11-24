import Logging
import PostgresNIO

/// A connection outside the pool, from ``Database/dedicatedConnection()``. It holds session state that must not leak
/// back into a pool, such as session advisory locks and `LISTEN`, and stays open until ``close()``.
public struct DedicatedConnection: DatabaseExecutor {
    let connection: PostgresConnection
    public let logger: Logger

    @discardableResult
    public func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        // PostgresNIO never answers a query sent on a closed connection.
        guard !connection.isClosed else { throw DBKitError.connectionClosed }
        return try await connection.query(query, logger: logger)
    }

    /// Closes the connection, which releases its advisory locks.
    public func close() async {
        try? await connection.close()
    }

    /// Throws when the connection no longer reaches the server, which also means its advisory locks are gone.
    /// Never waits on a lost connection.
    public func ping() async throws {
        _ = try await rows("SELECT 1")
    }

    /// Listens on `channel` and runs `consume` with the notifications sent to it from then on, e.g. with
    /// ``DatabaseExecutor/notify(_:payload:)``. Listening stops when `consume` returns. The sequence throws when the
    /// connection drops; open a new connection and listen again. `channel` goes into the `LISTEN` statement
    /// unescaped, so never pass user input.
    public func listen<Value>(
        on channel: String,
        consume: (PostgresNotificationSequence) async throws -> Value
    ) async throws -> Value {
        try await connection.listen(on: channel, consume: consume)
    }

    /// The single boolean a query such as `SELECT pg_try_advisory_lock(…)` returns.
    func bool(_ query: PostgresQuery) async throws -> Bool {
        try await rows(query).first?.decode(Bool.self) ?? false
    }

    /// Runs `query`, or throws ``DBKitError/connectionClosed`` when the connection is lost.
    private func rows(_ query: PostgresQuery) async throws -> [PostgresRow] {
        try await connection.rows(query, logger: logger).get()
    }
}
