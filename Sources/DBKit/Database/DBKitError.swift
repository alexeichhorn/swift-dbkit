/// Errors raised by DBKit itself. Database errors from PostgreSQL surface as `PSQLError`.
public enum DBKitError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidDatabaseURL(String)
    /// A query was sent in a transaction whose connection is already closed.
    case connectionClosed
    case missingColumn(String)
    case decodingFailed(column: String, type: String)

    public var description: String {
        switch self {
        case .invalidDatabaseURL(let reason): "invalid database URL: \(reason)"
        case .connectionClosed: "the connection is closed"
        case .missingColumn(let column): "result has no column \"\(column)\""
        case .decodingFailed(let column, let type): "cannot decode column \"\(column)\" as \(type)"
        }
    }
}
