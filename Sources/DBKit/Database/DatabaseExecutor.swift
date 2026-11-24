import Foundation
import Logging
import PostgresNIO

/// Something that runs queries: a ``Database`` or a ``Transaction``.
public protocol DatabaseExecutor: Sendable {
    var logger: Logger { get }

    /// Runs raw SQL. Interpolated values become bind parameters:
    /// `try await db.query("SELECT id, title FROM todos WHERE user_id = \(userID)").decode((Int64, String).self)`.
    func query(_ query: PostgresQuery) async throws -> PostgresRowSequence
}

extension DatabaseExecutor {
    /// Runs raw SQL and decodes each row as `model`. Select all of the model's columns, e.g. `SELECT todos.* …`.
    public func query<M: Model>(_ query: PostgresQuery, as model: M.Type) async throws -> [M.Base] {
        var models: [M.Base] = []
        for try await row in try await self.query(query) {
            models.append(try M.decodeBase(from: RowReader(row: row.makeRandomAccess(), prefix: "")))
        }
        return models
    }

    /// Runs the query and turns each row into a value as it arrives. A raw row keeps the network buffer it arrived in
    /// alive, which can be many times its size, so return the decoded value and not the row.
    func rows<Value>(_ rendered: RenderedSQL, _ transform: (PostgresRandomAccessRow) throws -> Value) async throws -> [Value] {
        var values: [Value] = []
        for try await row in try await query(postgresQuery(rendered)) {
            values.append(try transform(row.makeRandomAccess()))
        }
        return values
    }

    /// Runs an `INSERT`/`UPDATE`/`DELETE` and returns the number of affected rows. PostgresNIO doesn't expose
    /// the command tag, so the statement is wrapped in a counting CTE.
    func execute(_ rendered: RenderedSQL) async throws -> Int {
        let counting = RenderedSQL(
            sql: "WITH \"affected\" AS (\(rendered.sql) RETURNING 1) SELECT COUNT(*) FROM \"affected\"", binds: rendered.binds)
        return Int(try await rows(counting) { try $0[0].decode(Int64.self) }.first ?? 0)
    }

    func postgresQuery(_ rendered: RenderedSQL) throws -> PostgresQuery {
        var bindings = PostgresBindings(capacity: rendered.binds.count)
        for bind in rendered.binds {
            if let date = bind.value as? Date {
                bindings.append(MicrosecondTimestamp(date: date))
            } else {
                try bindings.append(bind.value)
            }
        }
        return PostgresQuery(unsafeSQL: rendered.sql, binds: bindings)
    }
}

/// Binds a `Date` rounded to the nearest microsecond. PostgresNIO rounds down, so a timestamp read from a row could be
/// written back one microsecond lower.
private struct MicrosecondTimestamp: PostgresNonThrowingEncodable {
    static let psqlType = PostgresDataType.timestamptz
    static let psqlFormat = PostgresFormat.binary
    /// PostgreSQL counts from 2000-01-01.
    static let epoch = Date(timeIntervalSince1970: 946_684_800)

    let date: Date

    func encode<JSONEncoder: PostgresJSONEncoder>(into byteBuffer: inout ByteBuffer, context: PostgresEncodingContext<JSONEncoder>) {
        byteBuffer.writeInteger(Int64((date.timeIntervalSince(Self.epoch) * 1_000_000).rounded()))
    }
}
