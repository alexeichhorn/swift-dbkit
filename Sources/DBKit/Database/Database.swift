import Foundation
import Logging
import NIOSSL
import PostgresNIO
import ServiceLifecycle

/// A connection pool, usable as a ``DatabaseExecutor`` and as a swift-service-lifecycle `Service`.
///
/// The pool only hands out connections while ``run()`` is running, so add the database to your `ServiceGroup`
/// (or run it in a task) before querying.
public final class Database: DatabaseExecutor, Service {
    /// The underlying client, for libraries that work with PostgresNIO directly (migrations, job queues).
    public let client: PostgresClient
    public let logger: Logger

    public init(client: PostgresClient, logger: Logger = Logger(label: "dbkit")) {
        self.client = client
        self.logger = logger
    }

    /// Creates a pool from a URL like `postgres://user:password@host:5432/database?sslmode=require`.
    ///
    /// `sslmode` follows libpq: `disable`, `prefer` (default), `require` (encrypted, unverified),
    /// `verify-full` (encrypted and verified). The pool keeps `connections.lowerBound` connections open and grows to
    /// `connections.upperBound`.
    public init(url: String, connections: ClosedRange<Int> = 0...20, logger: Logger = Logger(label: "dbkit")) throws {
        let url = try DatabaseURL(url)
        var configuration = PostgresClient.Configuration(url)
        configuration.options.minimumConnections = connections.lowerBound
        configuration.options.maximumConnections = connections.upperBound
        self.client = PostgresClient(configuration: configuration, backgroundLogger: logger)
        self.logger = logger
    }

    /// Runs the connection pool until the task is cancelled or the service group shuts down.
    public func run() async {
        await client.run()
    }

    @discardableResult
    public func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        try await client.query(query, logger: logger)
    }

    /// Runs `body` in a transaction on one pooled connection. It commits when `body` returns and rolls back when
    /// it throws, rethrowing the original error. Don't let the ``Transaction`` escape `body`.
    public func transaction<Result>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: (Transaction) async throws -> sending Result
    ) async throws -> sending Result {
        try await client.withConnection(isolation: isolation) { connection in
            let transaction = Transaction(connection: connection, logger: logger)
            try await transaction.query("BEGIN")
            let result: Result
            do {
                result = try await body(transaction)
            } catch {
                _ = try? await transaction.query("ROLLBACK")
                throw error
            }
            try await transaction.query("COMMIT")
            return result
        }
    }
}

/// An open transaction, passed to the closure of ``Database/transaction(isolation:_:)``.
public struct Transaction: DatabaseExecutor {
    /// The transaction's connection, for raw PostgresNIO access.
    public let connection: PostgresConnection
    public let logger: Logger

    @discardableResult
    public func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        // PostgresNIO never answers a query sent on a closed connection.
        guard !connection.isClosed else { throw DBKitError.connectionClosed }
        return try await connection.query(query, logger: logger)
    }

    /// Sets a PostgreSQL setting until the transaction ends (`set_config(name, value, true)`), so it never leaks to
    /// other users of the pooled connection: `try await tx.setLocal("statement_timeout", "5s")`.
    public func setLocal(_ name: String, _ value: String) async throws {
        _ = try await query("SELECT set_config(\(name), \(value), true)").collect()
    }
}

/// A parsed `postgres://` / `postgresql://` URL with an optional `sslmode` query parameter.
struct DatabaseURL: Sendable {
    enum TLS {
        case disable
        case prefer(TLSConfiguration)
        case require(TLSConfiguration)
    }

    let host: String
    let port: Int
    let username: String
    let password: String?
    let database: String?
    let tls: TLS

    init(_ url: String) throws {
        guard let components = URLComponents(string: url), ["postgres", "postgresql"].contains(components.scheme),
            let host = components.host, !host.isEmpty
        else { throw DBKitError.invalidDatabaseURL("expected postgres://user:password@host:port/database") }
        guard let username = components.user, !username.isEmpty else { throw DBKitError.invalidDatabaseURL("missing user") }
        let sslMode = components.queryItems?.first { $0.name == "sslmode" }?.value ?? "prefer"

        var unverified = TLSConfiguration.makeClientConfiguration()
        unverified.certificateVerification = .none
        switch sslMode {
        case "disable": tls = .disable
        case "allow", "prefer": tls = .prefer(unverified)
        case "require": tls = .require(unverified)
        case "verify-ca", "verify-full": tls = .require(.makeClientConfiguration())
        default: throw DBKitError.invalidDatabaseURL("unsupported sslmode \(sslMode)")
        }
        self.host = host
        self.port = components.port ?? 5432
        self.username = username
        self.password = components.password
        self.database = components.path.split(separator: "/").first.map(String.init)
    }
}

extension PostgresClient.Configuration {
    /// Parses `postgres://` / `postgresql://` URLs with an optional `sslmode` query parameter.
    public init(url: String) throws {
        self.init(try DatabaseURL(url))
    }

    init(_ url: DatabaseURL) {
        let tls: TLS =
            switch url.tls {
            case .disable: .disable
            case .prefer(let configuration): .prefer(configuration)
            case .require(let configuration): .require(configuration)
            }
        self.init(host: url.host, port: url.port, username: url.username, password: url.password, database: url.database, tls: tls)
    }
}
