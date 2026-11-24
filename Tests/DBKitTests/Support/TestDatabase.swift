import DBKit
import Foundation

/// Runs `body` in a transaction on the shared pool and always rolls it back, so its `CREATE TEMP TABLE`s and rows
/// vanish. Tests isolated this way run in parallel.
func withRollback(_ body: (Transaction) async throws -> Void) async throws {
    struct RolledBack: Error {}
    do {
        try await testDatabase().transaction { transaction in
            try await body(transaction)
            throw RolledBack()
        }
    } catch is RolledBack {}
}

/// For a test that needs several connections: creates the real table `name`, runs `body` and drops the table.
/// Name the table for the test, so tests running in parallel never share one.
func withRealTable(_ name: String, columns: String, _ body: (Database) async throws -> Void) async throws {
    let database = try testDatabase()
    let drop: PostgresQuery = "DROP TABLE IF EXISTS \(unescaped: name)"
    try await database.query(drop)
    try await database.query("CREATE TABLE \(unescaped: name) (\(unescaped: columns))")
    do {
        try await body(database)
    } catch {
        _ = try? await database.query(drop)
        throw error
    }
    try await database.query(drop)
}

/// The pool all integration tests share. It starts on first use and runs until the test process exits, since opening
/// a connection to a remote database takes over a second. Open another pool only to test the pool itself.
func testDatabase() throws -> Database {
    try sharedDatabase.get()
}

private let sharedDatabase: Result<Database, TestDatabaseError> = {
    do {
        let database = try Database(url: testDatabaseURL())
        Task { await database.run() }
        return .success(database)
    } catch {
        return .failure(TestDatabaseError(description: "cannot open the test database: \(error)"))
    }
}()

/// `DATABASE_URL` from the environment, or else from the nearest `.env` file above this one.
func testDatabaseURL() throws -> String {
    if let url = ProcessInfo.processInfo.environment["DATABASE_URL"] { return url }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    // One step per path component reaches the root, however `URL` treats going up from there.
    for _ in directory.pathComponents {
        if let contents = try? String(contentsOf: directory.appendingPathComponent(".env"), encoding: .utf8) {
            let line = contents.split(whereSeparator: \.isNewline).first { $0.hasPrefix("DATABASE_URL=") }
            guard let line else { break }
            return line.dropFirst("DATABASE_URL=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        directory.deleteLastPathComponent()
    }
    throw TestDatabaseError(description: "integration tests need DATABASE_URL, from the environment or from a .env file")
}

struct TestDatabaseError: Error, CustomStringConvertible {
    let description: String
}
