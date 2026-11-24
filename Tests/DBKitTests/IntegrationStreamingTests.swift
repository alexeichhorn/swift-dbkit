import DBKit
import Synchronization
import Testing

@Model(table: "stream_groups")
class StreamGroupModel {
    @Key var id: Int64
    var name: String
}

@Model(table: "stream_items")
class StreamItemModel {
    @Key var id: Int64
    var groupID: Int64?
    var name: String
    var note: String?
    @BelongsTo(key: "groupID") var group: StreamGroupModel?
}

@Model(table: "stream_probe")
class StreamProbeModel {
    @Key var id: Int64
}

/// A table no database has, for queries that must fail on the server.
@Model(table: "dbkit_stream_table_that_does_not_exist")
class StreamMissingTableModel {
    @Key var id: Int64
}

@Model(table: "stream_failures")
class StreamFailureModel {
    @Key var id: Int64
    var payload: String
    var value: Int32
}

/// `stream_items` with each `id` once more as `probe`, through a view.
@Model(table: "stream_decode_probes")
class StreamDecodeProbeModel {
    @Key var id: Int64
    var probe: StreamDecodeProbe
}

/// rust-dbkit's `DecodeProbe`: an `int8` that counts its decodes in `decodedStreamProbes` and fails to decode 3.
struct StreamDecodeProbe: SQLValue, Equatable {
    static var sqlTypeName: String { "bigint" }
    static var psqlType: PostgresDataType { .int8 }
    static var psqlFormat: PostgresFormat { .binary }

    struct DeliberateFailure: Error {}

    let value: Int64

    func encode<JSONEncoder: PostgresJSONEncoder>(into byteBuffer: inout ByteBuffer, context: PostgresEncodingContext<JSONEncoder>) {
        byteBuffer.writeInteger(value)
    }

    init<JSONDecoder: PostgresJSONDecoder>(
        from buffer: inout ByteBuffer, type: PostgresDataType, format: PostgresFormat, context: PostgresDecodingContext<JSONDecoder>
    ) throws {
        decodedStreamProbes.withLock { $0 += 1 }
        value = try Int64(from: &buffer, type: type, format: format, context: context)
        if value == 3 { throw DeliberateFailure() }
    }
}

private let decodedStreamProbes = Mutex(0)

/// Far more rows than a stream may read ahead, so evaluating all of them is unmistakable.
private let largeResultRows = 100_000
/// Rows a stream may evaluate beyond what the loop has read.
private let maxRowsReadAhead: Int64 = 1000

/// rust-dbkit's `integration_streaming.rs`. Each test has a pool of one connection, which keeps the `TEMP` tables in
/// scope for streams on the pool and makes a stream that keeps its connection block the next query. The suite runs
/// one test at a time, so it opens one connection at a time.
@Suite(.serialized, .timeLimit(.minutes(5))) struct IntegrationStreamingTests {
    @Test func streamPreservesFiltersOrderLimitOffsetAndUnloadedRelations() async throws {
        try await withStreamItems { db in
            let rows: [StreamItemModel] = try await readAll(
                StreamItemModel.query()
                    .filter(StreamItemModel.id > 1)
                    .orderBy(StreamItemModel.id.desc)
                    .offset(1)
                    .limit(2)
                    .stream(on: db))
            #expect(rows.map(\.id) == [3, 2])
            #expect(rows.map(\.note) == ["memo", ""])
        }
    }

    /// The name is bound in a closure that has returned before the stream runs.
    @Test func streamOwnsTemporaryQueryAndBoundValues() async throws {
        try await withStreamItems { db in
            let rows = try await {
                let name = String("猫 ' OR true --")
                return try await StreamItemModel.query().filter(StreamItemModel.name == name).stream(on: db)
            }()
            #expect(try await readAll(rows).map(\.id) == [3])
        }
    }

    /// With one connection, a stream that took it in `stream(on:)` would make the update wait forever.
    @Test func queryRunsOnFirstPollRatherThanStreamCreation() async throws {
        try await withStreamItems { db in
            let rows = try await StreamItemModel.query().filter(StreamItemModel.id == 1).stream(on: db)
            try await db.query("UPDATE stream_items SET name = 'changed' WHERE id = 1")
            #expect(try await readAll(rows).map(\.name) == ["changed"])
        }
    }

    @Test func largeStreamVisitsEveryRowOnceWithoutCollecting() async throws {
        try await withStreamItems { db in
            try await db.query("TRUNCATE stream_items")
            try await db.query("INSERT INTO stream_items SELECT n, NULL, repeat('猫', 100), NULL FROM generate_series(1, 10003) n")
            var expectedID: Int64 = 1
            for try await row in try await StreamItemModel.query().orderBy(StreamItemModel.id.asc).stream(on: db) {
                #expect(row.id == expectedID)
                #expect(row.name.count == 100)
                expectedID += 1
            }
            #expect(expectedID == 10004)
            try await expectNoCursorOrTransaction(on: db)
        }
    }

    @Test func streamYieldsEveryRowAroundFetchBatchBoundaries() async throws {
        try await withStreamItems { db in
            for rows in [999, 1000, 1001, 2000, 2001] {
                try await db.query(
                    PostgresQuery(
                        unsafeSQL: "CREATE OR REPLACE TEMP VIEW stream_probe AS SELECT n::BIGINT AS id FROM generate_series(1, \(rows)) n"))
                let ids = try await readAll(StreamProbeModel.query().stream(on: db)).map(\.id)
                #expect(ids == Array(1...Int64(rows)), "\(rows) rows")
                try await expectNoCursorOrTransaction(on: db)
            }
        }
    }

    @Test func emptyResultsZeroLimitAndOffsetPastEndFinishCleanly() async throws {
        try await withStreamItems { db in
            for query in [
                StreamItemModel.query().filter(StreamItemModel.id < 0),
                StreamItemModel.query().limit(0),
                StreamItemModel.query().orderBy(StreamItemModel.id.asc).offset(100),
            ] {
                #expect(try await readAll(query.stream(on: db)).isEmpty)
                try await expectNoCursorOrTransaction(on: db)
            }
        }
    }

    /// A `Decodable` type, as with `all(as:on:)`, and a `@Projection` type, on the pool and in a transaction.
    @Test func streamSupportsNamedProjectionsAndPreservesNulls() async throws {
        struct ItemSummary: Decodable, Equatable {
            let itemID: Int64
            let note: String?
        }

        @Projection struct ItemNote {
            let itemID: Int64
            let note: String?
        }

        try await withStreamItems { db in
            let summaries = try await readAll(
                StreamItemModel.query()
                    .select(StreamItemModel.id.as("item_id"), StreamItemModel.note.as("note"))
                    .orderBy(StreamItemModel.id.asc)
                    .stream(as: ItemSummary.self, on: db))
            #expect(
                summaries == [
                    ItemSummary(itemID: 1, note: nil),
                    ItemSummary(itemID: 2, note: ""),
                    ItemSummary(itemID: 3, note: "memo"),
                    ItemSummary(itemID: 4, note: nil),
                ])

            let notes = StreamItemModel.query()
                .select(ItemNote.columns(itemID: StreamItemModel.id, note: StreamItemModel.note))
                .orderBy(StreamItemModel.id.asc)
            let onThePool = try await readAll(notes.stream(on: db))
            #expect(onThePool.map(\.itemID) == [1, 2, 3, 4])
            #expect(onThePool.map(\.note) == [nil, "", "memo", nil])
            let inATransaction = try await db.transaction { tx in try await readAll(notes.stream(on: tx)) }
            #expect(inATransaction.map(\.itemID) == [1, 2, 3, 4])
            #expect(inATransaction.map(\.note) == [nil, "", "memo", nil])
        }
    }

    /// The grouped stream reads in a transaction, so typed tuples stream on both executors.
    @Test func streamSupportsDistinctGroupingHavingAndAggregateExpressions() async throws {
        try await withStreamItems { db in
            let groups = try await readAll(
                StreamItemModel.query()
                    .select(StreamItemModel.groupID)
                    .distinct()
                    .orderBy(StreamItemModel.groupID.asc)
                    .stream(on: db))
            #expect(groups == [1, 2, nil])

            let totals = try await db.transaction { tx in
                try await readAll(
                    StreamItemModel.query()
                        .select(StreamItemModel.groupID, SQL.count(StreamItemModel.id))
                        .groupBy(StreamItemModel.groupID)
                        .having(SQL.count(StreamItemModel.id) > 1)
                        .stream(on: tx))
            }
            #expect(totals.map(\.0) == [1])
            #expect(totals.map(\.1) == [2])
        }
    }

    @Test func streamSupportsRelationPathJoinsWithoutEagerLoading() async throws {
        try await withStreamItems { db in
            let rows = try await readAll(
                StreamItemModel.query()
                    .select(StreamItemModel.id, StreamItemModel.Relations.group.name)
                    .orderBy(StreamItemModel.id.asc)
                    .stream(on: db))
            #expect(rows.map(\.0) == [1, 2, 3, 4])
            #expect(rows.map(\.1) == ["north", "south", "north", nil])

            let ids = try await readAll(
                StreamItemModel.query()
                    .select(StreamItemModel.id)
                    .filter(StreamItemModel.Relations.group.name == "north")
                    .orderBy(StreamItemModel.id.asc)
                    .stream(on: db))
            #expect(ids == [1, 3])
        }
    }

    @Test func unpolledStreamDoesNotExecuteAndStreamingDoesNotCountOrRequery() async throws {
        try await withStreamItems { db in
            try await createCountingProbe(rows: 4, on: db)

            _ = try await StreamProbeModel.query().stream(on: db)
            #expect(try await evaluatedProbeRows(on: db) == 0, "creating a stream without reading it must not run its query")

            #expect(try await readAll(StreamProbeModel.query().stream(on: db)).map(\.id) == [1, 2, 3, 4])
            #expect(try await evaluatedProbeRows(on: db) == 4, "no hidden count query or replay")
        }
    }

    /// Each row decodes when the loop reads it, and the loop ends with the error of the third.
    @Test func streamDecodesOnDemandAndStopsAfterFirstDecodeError() async throws {
        try await withStreamItems { db in
            try await db.query("CREATE TEMP VIEW stream_decode_probes AS SELECT id, id AS probe FROM stream_items")
            decodedStreamProbes.withLock { $0 = 0 }
            let rows = try await StreamDecodeProbeModel.query().orderBy(StreamDecodeProbeModel.id.asc).stream(on: db)
            #expect(decodedStreamProbes.withLock { $0 } == 0)

            var read: [Int64] = []
            let error = try await #require(throws: DBKitError.self) {
                for try await row in rows {
                    read.append(row.probe.value)
                    #expect(decodedStreamProbes.withLock { $0 } == read.count)
                }
            }
            #expect(error == .decodingFailed(column: "probe", type: "StreamDecodeProbe"))
            #expect(read == [1, 2])
            #expect(decodedStreamProbes.withLock { $0 } == 3, "must not decode row four after an error")
            try await expectNoCursorOrTransaction(on: db)
        }
    }

    /// The row after the first read-ahead window divides by zero. PostgreSQL may withhold rows that share a fetch with
    /// the failing one, but collecting the whole result before yielding would lose every successful row.
    @Test func streamYieldsRowsBeforeALaterDatabaseError() async throws {
        try await withStreamItems { db in
            let failingRow = maxRowsReadAhead + 1
            try await db.query(
                PostgresQuery(
                    unsafeSQL: """
                        CREATE TEMP VIEW stream_failures AS
                            SELECT n::BIGINT AS id, 'x' AS payload, 1 / (\(failingRow) - n) AS value
                            FROM generate_series(1, \(failingRow)) AS n
                        """))
            var nextID: Int64 = 1
            let error = try await #require(throws: PSQLError.self) {
                for try await row in try await StreamFailureModel.query().stream(on: db) {
                    #expect(row.id == nextID)
                    nextID += 1
                }
            }
            #expect(nextID > 1, "rows before the server failure must be yielded")
            #expect(error.serverInfo?[.sqlState] == "22012")
            try await expectNoCursorOrTransaction(on: db)
        }
    }

    /// The query fails on the server, here because its table doesn't exist, so the loop throws before any row.
    @Test func initialQueryErrorIsAnItemThenTheStreamEnds() async throws {
        try await withStreamItems { db in
            let error = try await #require(throws: PSQLError.self) {
                for try await _ in try await StreamMissingTableModel.query().stream(on: db) {}
            }
            #expect(error.serverInfo?[.sqlState] == "42P01")
            try await expectNoCursorOrTransaction(on: db)
        }
    }

    /// The pool shuts down when `run()` is cancelled. A stream that held a connection before its first row would keep
    /// it from shutting down.
    @Test func closedPoolErrorIsReportedDuringIteration() async throws {
        let db = try Database(url: testDatabaseURL(), connections: 0...1)
        let running = Task { await db.run() }
        try await db.query("SELECT 1")
        let rows = try await StreamItemModel.query().stream(on: db)
        running.cancel()
        await running.value

        await #expect(throws: (any Error).self) {
            for try await _ in rows {}
        }
    }

    /// rust-dbkit reports a pool timeout here. `PostgresClient` waits for a free connection without a limit, so the
    /// stream waits on its first row instead; `stream(on:)` itself must not wait, or the transaction would wait for
    /// itself.
    @Test func aStreamOnAnExhaustedPoolWaitsForAConnectionWhenIterated() async throws {
        try await withStreamItems { db in
            let reader = try await db.transaction { _ in
                let rows = try await StreamItemModel.query().stream(on: db)
                return Task { try await readAll(rows).count }
            }
            #expect(try await reader.value == 4)
            try await expectNoCursorOrTransaction(on: db)
        }
    }

    /// The transaction holds the only connection, so the stream waits for it until its task is cancelled.
    @Test func droppingStreamWhileWaitingForConnectionDoesNotLeakPoolCapacity() async throws {
        try await withStreamItems { db in
            try await db.transaction { _ in
                let reader = Task {
                    for try await _ in try await StreamItemModel.query().stream(on: db) {}
                }
                reader.cancel()
                await #expect(throws: (any Error).self) { try await reader.value }
            }
            try await expectNoCursorOrTransaction(on: db)
        }
    }

    /// Between two rows, the stream's connection is lent to it and waits in the stream's transaction.
    @Test func droppingPartiallyConsumedStreamReleasesItsConnection() async throws {
        try await withStreamItems { db in
            let pid = try #require(try await backendPID(on: db))
            for try await row in try await StreamItemModel.query().orderBy(StreamItemModel.id.asc).stream(on: db) {
                #expect(row.id == 1)
                let state = try await testDatabase().query("SELECT state FROM pg_stat_activity WHERE pid = \(pid)").collect()
                    .first?.decode(String.self)
                #expect(state == "idle in transaction", "an active stream must keep its connection")
                break
            }
            try await expectNoCursorOrTransaction(on: db)
        }
    }

    @Test func droppingPoolStreamEarlyStopsTheQuery() async throws {
        try await withStreamItems { db in
            try await createCountingProbe(rows: largeResultRows, on: db)
            for try await row in try await StreamProbeModel.query().stream(on: db) {
                #expect(row.id == 1)
                break
            }
            try await expectNoCursorOrTransaction(on: db)
            let evaluated = try #require(try await evaluatedProbeRows(on: db))
            #expect(evaluated <= maxRowsReadAhead, "the stream left early evaluated \(evaluated) of \(largeResultRows) rows")
        }
    }

    @Test func droppingTransactionStreamEarlyStopsTheQueryAndKeepsTransactionUsable() async throws {
        try await withStreamItems { db in
            try await db.transaction { tx in
                try await createCountingProbe(rows: largeResultRows, on: tx)
                for try await row in try await StreamProbeModel.query().stream(on: tx) {
                    #expect(row.id == 1)
                    break
                }
                let evaluated = try #require(try await evaluatedProbeRows(on: tx))
                #expect(evaluated <= maxRowsReadAhead, "the stream left early evaluated \(evaluated) of \(largeResultRows) rows")
                try await tx.query("INSERT INTO stream_items VALUES (5, 1, 'after drop', NULL)")
            }
            #expect(try await StreamItemModel.query().count(on: db) == 5)
            try await expectNoCursorOrTransaction(on: db)
        }
    }

    @Test func repeatedStreamsNeitherCollideNorAccumulatePreparedStatements() async throws {
        try await withStreamItems { db in
            let statementsBefore = try #require(try await preparedStatementCount(on: db))

            for _ in 0..<20 {
                for try await row in try await StreamItemModel.query().orderBy(StreamItemModel.id.asc).stream(on: db) {
                    #expect(row.id == 1)
                    break
                }
                #expect(try await readAll(StreamItemModel.query().stream(on: db)).count == 4)
            }
            try await expectNoCursorOrTransaction(on: db)

            // Streams left early inside one transaction must not block later streams in it.
            try await db.transaction { tx in
                for _ in 0..<20 {
                    for try await row in try await StreamItemModel.query().orderBy(StreamItemModel.id.asc).stream(on: tx) {
                        #expect(row.id == 1)
                        break
                    }
                    #expect(try await readAll(StreamItemModel.query().stream(on: tx)).count == 4)
                }
            }
            try await expectNoCursorOrTransaction(on: db)

            let added = try #require(try await preparedStatementCount(on: db)) - statementsBefore
            #expect(added <= 5, "40 streams added \(added) prepared statements")
        }
    }

    /// The iterator stays alive after its last row, as rust-dbkit's stream variable does.
    @Test func exhaustionReleasesConnectionEvenWhileStreamVariableIsAlive() async throws {
        try await withStreamItems { db in
            var rows = try await StreamItemModel.query().stream(on: db).makeAsyncIterator()
            var count = 0
            while try await rows.next() != nil { count += 1 }
            #expect(count == 4)
            try await expectNoCursorOrTransaction(on: db)
            #expect(try await rows.next() == nil)
        }
    }

    @Test func streamReadsUncommittedTransactionRowsAndCanBeDroppedBeforeRollback() async throws {
        try await withStreamItems { db in
            struct Rollback: Error {}
            await #expect(throws: Rollback.self) {
                try await db.transaction { tx in
                    try await tx.query("INSERT INTO stream_items VALUES (5, 1, 'uncommitted', NULL)")
                    for try await row in try await StreamItemModel.query().orderBy(StreamItemModel.id.desc).stream(on: tx) {
                        #expect(row.id == 5, "the transaction's own insert")
                        break
                    }
                    #expect(try await StreamItemModel.query().count(on: tx) == 5)
                    throw Rollback()
                }
            }
            // A closure whose only `try` is inside `#expect` would be inferred as non-throwing.
            let remaining = try await StreamItemModel.query().count(on: db)
            #expect(remaining == 4)
        }
    }

    /// rust-dbkit's transaction mutex is the transaction's connection here, which answers the count after the locking
    /// stream's last row.
    @Test func exhaustedTransactionStreamReleasesMutexBeforeCommit() async throws {
        try await withStreamItems { db in
            try await db.transaction { tx in
                try await tx.query("INSERT INTO stream_items VALUES (5, 1, 'committed', NULL)")
                let locked = try await readAll(StreamItemModel.query().filter(StreamItemModel.id == 5).forUpdate().stream(on: tx))
                #expect(locked.map(\.id) == [5])
                #expect(try await StreamItemModel.query().count(on: tx) == 5)
            }
            #expect(try await StreamItemModel.query().count(on: db) == 5)
        }
    }

    /// The failed query aborts the transaction, so `db.transaction` rolls it back and rethrows.
    @Test func transactionQueryErrorReleasesMutexForRollback() async throws {
        try await withStreamItems { db in
            let error = try await #require(throws: PSQLError.self) {
                try await db.transaction { tx in
                    for try await _ in try await StreamMissingTableModel.query().stream(on: tx) {}
                }
            }
            #expect(error.serverInfo?[.sqlState] == "42P01")
            try await expectNoCursorOrTransaction(on: db)
        }
    }

    /// A row that doesn't decode fails on the client, so the transaction isn't aborted and the cursor is closed.
    /// rust-dbkit decodes the `bigint` id as a `String` tuple. A typed tuple here always matches its column, and
    /// PostgresNIO reads any column as a `String`, so a `Decodable` type reads it as a `Bool`. The transaction commits
    /// where rust-dbkit rolls back, since it wrote nothing.
    @Test func transactionRemainsUsableAfterClientSideDecodeError() async throws {
        struct MistypedItem: Decodable {
            let id: Bool
        }

        try await withStreamItems { db in
            try await db.transaction { tx in
                await #expect(throws: PostgresDecodingError.self) {
                    for try await _ in try await StreamItemModel.query()
                        .select(StreamItemModel.id.as("id"))
                        .stream(as: MistypedItem.self, on: tx)
                    {}
                }
                let count = try await StreamItemModel.query().count(on: tx)
                #expect(count == 4)
                #expect(try await integer("SELECT count(*) FROM pg_cursors WHERE name <> ''", on: tx) == 0)
            }
            try await expectNoCursorOrTransaction(on: db)
        }
    }
}

/// rust-dbkit's `database()`: two groups and four items as `TEMP` tables, on a pool of one connection.
private func withStreamItems(_ body: (Database) async throws -> Void) async throws {
    try await withPoolOfOneConnection { db in
        try await db.query("SET statement_timeout = '5s'")
        try await db.query("CREATE TEMP TABLE stream_groups (id BIGINT PRIMARY KEY, name TEXT NOT NULL)")
        try await db.query("CREATE TEMP TABLE stream_items (id BIGINT PRIMARY KEY, group_id BIGINT, name TEXT NOT NULL, note TEXT)")
        try await db.query("INSERT INTO stream_groups VALUES (1, 'north'), (2, 'south')")
        try await db.query(
            "INSERT INTO stream_items VALUES (1, 1, 'alpha', NULL), (2, 2, 'beta', ''), (3, 1, '猫 '' OR true --', 'memo'), (4, NULL, 'delta', NULL)"
        )
        try await body(db)
    }
}

/// Every row of a stream, in order.
private func readAll<Rows: AsyncSequence>(_ rows: Rows) async throws -> [Rows.Element] {
    var all: [Rows.Element] = []
    for try await row in rows { all.append(row) }
    return all
}

/// Creates the `stream_probe` view, which counts every row PostgreSQL evaluates in the sequence `stream_calls`.
private func createCountingProbe(rows: Int, on executor: some DatabaseExecutor) async throws {
    _ = try await executor.query("CREATE TEMP SEQUENCE stream_calls")
    _ = try await executor.query(
        PostgresQuery(unsafeSQL: "CREATE TEMP VIEW stream_probe AS SELECT nextval('stream_calls') AS id FROM generate_series(1, \(rows))"))
}

private func evaluatedProbeRows(on executor: some DatabaseExecutor) async throws -> Int64? {
    try await integer("SELECT CASE WHEN is_called THEN last_value ELSE 0 END FROM stream_calls", on: executor)
}

private func preparedStatementCount(on db: Database) async throws -> Int64? {
    try await integer("SELECT count(*) FROM pg_prepared_statements", on: db)
}

private func backendPID(on db: Database) async throws -> Int32? {
    try await db.query("SELECT pg_backend_pid()").collect().first?.decode(Int32.self)
}
