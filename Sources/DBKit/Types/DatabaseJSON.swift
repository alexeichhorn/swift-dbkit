import PostgresNIO

/// A `Codable` value stored in a `jsonb` column.
///
/// ```swift
/// struct Preferences: Codable, DatabaseJSON { var theme: String }
/// ```
public protocol DatabaseJSON: SQLValue, Codable {}

extension DatabaseJSON {
    public static var sqlTypeName: String { "jsonb" }
}
