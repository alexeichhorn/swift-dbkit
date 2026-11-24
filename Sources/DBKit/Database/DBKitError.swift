/// Errors raised by DBKit itself. Database errors from PostgreSQL surface as `PSQLError`.
public enum DBKitError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidDatabaseURL(String)
    /// A dedicated connection was requested from a database created with `Database(client:)`, which has no URL.
    case missingDatabaseURL
    /// A query was sent on a dedicated connection or in a transaction whose connection is already closed.
    case connectionClosed
    case invalidVector(String)
    case missingColumn(String)
    case decodingFailed(column: String, type: String)
    /// An active-model update or save found no row for the primary key.
    case rowNotFound
    case migrationFailed(String)

    public var description: String {
        switch self {
        case .invalidDatabaseURL(let reason): "invalid database URL: \(reason)"
        case .missingDatabaseURL: "a dedicated connection needs the database URL; create the database with Database(url:)"
        case .connectionClosed: "the connection is closed"
        case .invalidVector(let reason): "invalid vector: \(reason)"
        case .missingColumn(let column): "result has no column \"\(column)\""
        case .decodingFailed(let column, let type): "cannot decode column \"\(column)\" as \(type)"
        case .rowNotFound: "no row matches the primary key"
        case .migrationFailed(let reason): "migration failed: \(reason)"
        }
    }
}
