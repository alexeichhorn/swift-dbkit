import NIOCore
import PostgresNIO

/// A PostgreSQL `interval`, stored like PostgreSQL does: months, days and microseconds are separate
/// because their lengths vary.
public struct Interval: Sendable, Hashable, CustomStringConvertible {
    public var months: Int32
    public var days: Int32
    public var microseconds: Int64

    public init(months: Int32 = 0, days: Int32 = 0, microseconds: Int64 = 0) {
        self.months = months
        self.days = days
        self.microseconds = microseconds
    }

    public static func days(_ days: Int32) -> Interval { Interval(days: days) }
    public static func hours(_ hours: Int64) -> Interval { Interval(microseconds: hours * 3_600_000_000) }
    public static func minutes(_ minutes: Int64) -> Interval { Interval(microseconds: minutes * 60_000_000) }
    public static func seconds(_ seconds: Int64) -> Interval { Interval(microseconds: seconds * 1_000_000) }

    public var description: String { "\(months) mons \(days) days \(microseconds) us" }
}

extension Interval: SQLValue {
    public static var sqlTypeName: String { "interval" }
    public static var psqlType: PostgresDataType { .interval }
    public static var psqlFormat: PostgresFormat { .binary }

    public func encode<JSONEncoder: PostgresJSONEncoder>(into byteBuffer: inout ByteBuffer, context: PostgresEncodingContext<JSONEncoder>) {
        byteBuffer.writeInteger(microseconds)
        byteBuffer.writeInteger(days)
        byteBuffer.writeInteger(months)
    }

    public init<JSONDecoder: PostgresJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: PostgresDataType,
        format: PostgresFormat,
        context: PostgresDecodingContext<JSONDecoder>
    ) throws {
        guard format == .binary, let microseconds = buffer.readInteger(as: Int64.self), let days = buffer.readInteger(as: Int32.self),
            let months = buffer.readInteger(as: Int32.self)
        else { throw PostgresDecodingError.Code.failure }
        self.init(months: months, days: days, microseconds: microseconds)
    }
}
