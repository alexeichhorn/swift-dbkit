import Foundation
import PostgresNIO

/// A Swift type stored in one database column. `Optional` marks a nullable column.
public protocol SQLType: Sendable {
    associatedtype NonNull: SQLValue

    /// The value as a bind parameter, or `NULL`.
    var sqlNode: SQLNode { get }

    static func decode(from cell: PostgresCell) throws -> Self
}

/// A non-null value that can be bound as a query parameter and decoded from a result column.
public protocol SQLValue: SQLType, SQLArgument, PostgresEncodable, PostgresDecodable where NonNull == Self, Value == Self {
    /// PostgreSQL type name, used for `CAST` and typed placeholders.
    static var sqlTypeName: String { get }
}

extension SQLValue {
    public var sqlNode: SQLNode { .bind(Bind(self)) }

    public static func decode(from cell: PostgresCell) throws -> Self {
        try cell.decode(Self.self)
    }
}

extension Optional: SQLType where Wrapped: SQLValue {
    public typealias NonNull = Wrapped

    public var sqlNode: SQLNode { map(\.sqlNode) ?? .null }

    public static func decode(from cell: PostgresCell) throws -> Self {
        cell.bytes == nil ? nil : try Wrapped.decode(from: cell)
    }
}

extension Bool: SQLValue { public static var sqlTypeName: String { "boolean" } }
extension String: SQLValue { public static var sqlTypeName: String { "text" } }
extension UUID: SQLValue { public static var sqlTypeName: String { "uuid" } }
extension Date: SQLValue { public static var sqlTypeName: String { "timestamptz" } }
extension Data: SQLValue { public static var sqlTypeName: String { "bytea" } }

extension Int16: SQLValue { public static var sqlTypeName: String { "smallint" } }
extension Int32: SQLValue { public static var sqlTypeName: String { "integer" } }
extension Int64: SQLValue { public static var sqlTypeName: String { "bigint" } }
extension Int: SQLValue { public static var sqlTypeName: String { "bigint" } }
extension Float: SQLValue { public static var sqlTypeName: String { "real" } }
extension Double: SQLValue { public static var sqlTypeName: String { "double precision" } }
extension Decimal: SQLValue { public static var sqlTypeName: String { "numeric" } }

/// PostgreSQL arrays such as `text[]` or `bigint[]`.
extension Array: SQLType, SQLArgument, SQLValue
where Element: SQLValue & PostgresArrayEncodable & PostgresArrayDecodable, Element._DecodableType == Element {
    public typealias NonNull = Self
    public typealias Value = Self
    public static var sqlTypeName: String { "\(Element.sqlTypeName)[]" }
}
