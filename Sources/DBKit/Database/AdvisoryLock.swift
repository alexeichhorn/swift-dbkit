/// A session advisory lock with a name, to make sure only one process does a piece of work.
///
/// PostgreSQL derives the lock key from the name (`hashtextextended(name, 0)`), so every session using the same name
/// contends for the same lock. A session lock belongs to its connection, so it is taken on a ``DedicatedConnection``
/// and held until ``release(on:)`` or until that connection closes.
public struct AdvisoryLock: Sendable, Hashable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    /// Takes the lock unless another session holds it; never waits. Taking it twice on one connection needs two
    /// releases.
    public func tryAcquire(on connection: DedicatedConnection) async throws -> Bool {
        try await connection.bool("SELECT pg_try_advisory_lock(hashtextextended(\(name), 0))")
    }

    /// Releases the lock. Returns `false` when `connection` didn't hold it.
    @discardableResult
    public func release(on connection: DedicatedConnection) async throws -> Bool {
        try await connection.bool("SELECT pg_advisory_unlock(hashtextextended(\(name), 0))")
    }
}
