import DBKit
import Foundation

/// The migration files of one test, in a directory of their own.
struct MigrationFiles {
    let directory: URL

    func write(_ sql: String, to file: String) throws {
        try sql.write(to: directory.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    func remove(_ file: String) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent(file))
    }
}

/// Runs `body` with an empty directory and an empty `_dbkit_migrations`, then drops that table, runs `cleanup` and
/// removes the directory. Both also run first, in case an earlier run stopped halfway.
///
/// `db.migrate` always records in `_dbkit_migrations` and fails on an applied version without its file, so every
/// migration test needs that table to itself: they run one at a time in the serialized suite `MigrationsTests`.
func withMigrations(cleanup: [PostgresQuery] = [], _ body: (Database, MigrationFiles) async throws -> Void) async throws {
    let db = try testDatabase()
    let reset = cleanup + ["DROP TABLE IF EXISTS _dbkit_migrations"]
    for query in reset { try await db.query(query) }
    let files = MigrationFiles(directory: FileManager.default.temporaryDirectory.appendingPathComponent("dbkit-migrations-\(UUID())"))
    try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: files.directory) }
    do {
        try await body(db, files)
    } catch {
        for query in reset { _ = try? await db.query(query) }
        throw error
    }
    for query in reset { try await db.query(query) }
}

func tableExists(_ name: String, on executor: some DatabaseExecutor) async throws -> Bool {
    try await executor.query("SELECT to_regclass(\(name)) IS NOT NULL").collect().first?.decode(Bool.self) ?? false
}
