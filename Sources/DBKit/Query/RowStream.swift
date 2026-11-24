import PostgresNIO

/// Rows of a streamed query, read through a server-side cursor and decoded as they arrive. See
/// ``Query/stream(on:)-(Database)``.
public struct RowStream<Row>: AsyncSequence, Sendable {
    let query: PostgresQuery
    let executor: any CursorExecutor
    /// Turns a row into a model, a tuple of selected values or a `Decodable` type.
    let decode: @Sendable (PostgresRandomAccessRow) throws -> Row

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(stream: self)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        let stream: RowStream
        /// Opened with the first row. Dropping the iterator drops the cursor, which ends it.
        var cursor: Cursor?

        public mutating func next() async throws -> Row? {
            try Task.checkCancellation()
            if cursor == nil { cursor = try await Cursor.open(stream.query, on: stream.executor) }
            guard let row = try await cursor?.next() else { return nil }
            return try stream.decode(row.makeRandomAccess())
        }
    }
}
