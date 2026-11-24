/// A Swift type stored in one database column. `Optional` marks a nullable column.
public protocol SQLType: Sendable {
    associatedtype NonNull: SQLValue
}

/// A non-null value that can be bound as a query parameter.
public protocol SQLValue: SQLType, SQLArgument where NonNull == Self, Value == Self {}

extension SQLValue {
    public var sqlNode: SQLNode { .bind(Bind(self)) }
}

extension Optional: SQLType where Wrapped: SQLValue {
    public typealias NonNull = Wrapped
}

extension Bool: SQLValue {}
extension String: SQLValue {}
extension Int16: SQLValue {}
extension Int32: SQLValue {}
extension Int64: SQLValue {}
extension Int: SQLValue {}
