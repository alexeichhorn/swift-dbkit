import PostgresNIO

/// A Swift type stored in one database column. `Optional` marks a nullable column.
public protocol SQLType: Sendable {
    associatedtype NonNull: SQLValue

    static func decode(from cell: PostgresCell) throws -> Self
}

/// A non-null value that can be bound as a query parameter and decoded from a result column.
public protocol SQLValue: SQLType, SQLArgument, PostgresEncodable, PostgresDecodable where NonNull == Self, Value == Self {}

extension SQLValue {
    public var sqlNode: SQLNode { .bind(Bind(self)) }

    public static func decode(from cell: PostgresCell) throws -> Self {
        try cell.decode(Self.self)
    }
}

extension Optional: SQLType where Wrapped: SQLValue {
    public typealias NonNull = Wrapped

    public static func decode(from cell: PostgresCell) throws -> Self {
        cell.bytes == nil ? nil : try Wrapped.decode(from: cell)
    }
}

extension Bool: SQLValue {}
extension String: SQLValue {}
extension Int16: SQLValue {}
extension Int32: SQLValue {}
extension Int64: SQLValue {}
extension Int: SQLValue {}
