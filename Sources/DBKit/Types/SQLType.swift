import Foundation
import PostgresNIO

/// A Swift type stored in one database column. `Optional` marks a nullable column.
///
/// The `As…` associated types carry nullability into results: `String.AsBool` is `Bool`, `String?.AsBool` is `Bool?`.
public protocol SQLType: Sendable {
    associatedtype NonNull: SQLValue
    associatedtype AsBool
    associatedtype AsString
    associatedtype AsDouble

    /// The value as a bind parameter, or `NULL`.
    var sqlNode: SQLNode { get }

    static func decode(from cell: PostgresCell) throws -> Self
}

/// A non-null value that can be bound as a query parameter and decoded from a result column.
public protocol SQLValue: SQLType, SQLArgument, PostgresEncodable, PostgresDecodable
where NonNull == Self, Value == Self, AsBool == Bool, AsString == String, AsDouble == Double {
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
    public typealias AsBool = Bool?
    public typealias AsString = String?
    public typealias AsDouble = Double?

    public var sqlNode: SQLNode { map(\.sqlNode) ?? .null }

    public static func decode(from cell: PostgresCell) throws -> Self {
        cell.bytes == nil ? nil : try Wrapped.decode(from: cell)
    }
}

/// Types that support `+` and `-` in SQL: numbers and intervals.
public protocol SQLAdditive: SQLValue {}

/// Numeric types that support `*` and `/` in SQL expressions.
public protocol SQLNumeric: SQLAdditive {}

/// Integer types that support bitwise operators in SQL expressions.
public protocol SQLInteger: SQLNumeric {}

/// `Int16`, `Int32` and `Int64`, the integers whose Swift type names their width. Bitwise operators between integer
/// types take a plain value only of these, so an untyped literal, which defaults to `Int`, takes the other operand's type.
public protocol SQLSizedInteger: SQLInteger, SQLMixedNumeric {}

/// A number that arithmetic mixes with numbers of other types, or its optional: the integers, `Float` and `Double`.
/// Each `With…` is PostgreSQL's result type with an operand of that type, optional when `Self` is; with a `Double`
/// operand it is `AsDouble`. Swift's `Int` is `bigint`, so it mixes as `Int64`.
public protocol SQLMixedNumeric: SQLType where NonNull: SQLMixedNumeric {
    associatedtype WithInt16
    associatedtype WithInt32
    associatedtype WithInt64
    associatedtype WithFloat
}

/// Types PostgreSQL casts to and from `text`, which `cast(to:)` accepts on either side of a `String`.
public protocol SQLTextCastable: SQLValue {}

/// A type that `cast(to:)` also reaches from one other type, its `CastPartner`: `Int32` and `Bool` from each other, and
/// `Date` from `Date`.
public protocol SQLCastPartner: SQLValue {
    associatedtype CastPartner: SQLValue
}

extension Bool: SQLTextCastable, SQLCastPartner {
    public static var sqlTypeName: String { "boolean" }
    public typealias CastPartner = Int32
}
extension String: SQLTextCastable { public static var sqlTypeName: String { "text" } }
extension UUID: SQLTextCastable { public static var sqlTypeName: String { "uuid" } }
extension Date: SQLTextCastable, SQLCastPartner {
    public static var sqlTypeName: String { "timestamptz" }
    public typealias CastPartner = Date
}
extension Data: SQLValue { public static var sqlTypeName: String { "bytea" } }

extension Int16: SQLSizedInteger, SQLTextCastable {
    public static var sqlTypeName: String { "smallint" }
    public typealias WithInt16 = Int16
    public typealias WithInt32 = Int32
    public typealias WithInt64 = Int64
    public typealias WithFloat = Double
}
extension Int32: SQLSizedInteger, SQLTextCastable, SQLCastPartner {
    public static var sqlTypeName: String { "integer" }
    public typealias CastPartner = Bool
    public typealias WithInt16 = Int32
    public typealias WithInt32 = Int32
    public typealias WithInt64 = Int64
    public typealias WithFloat = Double
}
extension Int64: SQLSizedInteger, SQLTextCastable {
    public static var sqlTypeName: String { "bigint" }
    public typealias WithInt16 = Int64
    public typealias WithInt32 = Int64
    public typealias WithInt64 = Int64
    public typealias WithFloat = Double
}
extension Int: SQLInteger, SQLMixedNumeric, SQLTextCastable {
    public static var sqlTypeName: String { "bigint" }
    public typealias WithInt16 = Int64
    public typealias WithInt32 = Int64
    public typealias WithInt64 = Int64
    public typealias WithFloat = Double
}
extension Float: SQLNumeric, SQLMixedNumeric, SQLTextCastable {
    public static var sqlTypeName: String { "real" }
    public typealias WithInt16 = Double
    public typealias WithInt32 = Double
    public typealias WithInt64 = Double
    public typealias WithFloat = Float
}
extension Double: SQLNumeric, SQLMixedNumeric, SQLTextCastable {
    public static var sqlTypeName: String { "double precision" }
    public typealias WithInt16 = Double
    public typealias WithInt32 = Double
    public typealias WithInt64 = Double
    public typealias WithFloat = Double
}
extension Decimal: SQLNumeric, SQLTextCastable { public static var sqlTypeName: String { "numeric" } }

extension Optional: SQLMixedNumeric where Wrapped: SQLMixedNumeric & SQLValue {
    public typealias WithInt16 = Wrapped.WithInt16?
    public typealias WithInt32 = Wrapped.WithInt32?
    public typealias WithInt64 = Wrapped.WithInt64?
    public typealias WithFloat = Wrapped.WithFloat?
}

/// PostgreSQL arrays such as `text[]` or `bigint[]`.
extension Array: SQLType, SQLArgument, SQLValue
where Element: SQLValue & PostgresArrayEncodable & PostgresArrayDecodable, Element._DecodableType == Element {
    public typealias NonNull = Self
    public typealias Value = Self
    public static var sqlTypeName: String { "\(Element.sqlTypeName)[]" }
}
