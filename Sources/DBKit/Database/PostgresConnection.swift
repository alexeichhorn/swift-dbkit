import Logging
import NIOCore
import PostgresNIO

extension PostgresConnection {
    /// Runs `query`, or fails with ``DBKitError/connectionClosed`` when the connection is lost. PostgresNIO never answers
    /// a query sent on a closed connection, so the check and the send happen together on the connection's event loop.
    ///
    /// The query is queued when this returns, ahead of any query sent later, and runs whether or not the result is
    /// awaited.
    func rows(_ query: PostgresQuery, logger: Logger) -> EventLoopFuture<[PostgresRow]> {
        eventLoop.flatSubmit {
            guard !self.isClosed else { return self.eventLoop.makeFailedFuture(DBKitError.connectionClosed) }
            return self.query(query, logger: logger).map(\.rows)
        }
    }
}
