import DBKit
import Foundation
import Testing

/// rust-dbkit's `migrations.rs`, against `db.migrate`. Every migration test shares `_dbkit_migrations`, so this suite
/// runs them one at a time; the kit's migration tests join it from `IntegrationTests.swift`.
@Suite(.serialized) struct MigrationsTests {
    @Test func migrateAppliesSimpleMigrationFile() async throws {
        try await withMigrations(cleanup: ["DROP TABLE IF EXISTS dbkit_mig_apply"]) { db, files in
            try files.write(
                "CREATE TABLE dbkit_mig_apply (id BIGSERIAL PRIMARY KEY, note TEXT NOT NULL);", to: "1_create_dbkit_mig_apply.sql")
            try await db.migrate(files.directory)
            #expect(try await tableExists("dbkit_mig_apply", on: db))
        }
    }

    @Test func migrateIsIdempotentWhenNoNewMigrationsExist() async throws {
        try await withMigrations(cleanup: ["DROP TABLE IF EXISTS dbkit_mig_idempotent"]) { db, files in
            try files.write("CREATE TABLE dbkit_mig_idempotent (id BIGSERIAL PRIMARY KEY);", to: "1_create_dbkit_mig_idempotent.sql")
            try await db.migrate(files.directory)
            try await db.migrate(files.directory)
            #expect(try await integer("SELECT count(*) FROM _dbkit_migrations WHERE version = 1", on: db) == 1)
        }
    }

    /// `10_…` sorts before `9_…` by name, so the versions also have to compare as numbers.
    @Test func migrateRespectsMigrationOrderByVersion() async throws {
        try await withMigrations(cleanup: ["DROP TABLE IF EXISTS dbkit_mig_ordering"]) { db, files in
            try files.write("CREATE TABLE dbkit_mig_ordering (id BIGSERIAL PRIMARY KEY);", to: "9_create_dbkit_mig_ordering.sql")
            try files.write(
                "ALTER TABLE dbkit_mig_ordering ADD COLUMN after_create TEXT NOT NULL DEFAULT '';", to: "10_alter_dbkit_mig_ordering.sql")
            try await db.migrate(files.directory)
            let columns = try await db.query(
                "SELECT column_name FROM information_schema.columns WHERE table_name = 'dbkit_mig_ordering' ORDER BY ordinal_position"
            ).collect().map { try $0.decode(String.self) }
            #expect(columns == ["id", "after_create"])
        }
    }

    @Test func migrateMapsInvalidSQLToMigrationErrorVariant() async throws {
        try await withMigrations { db, files in
            try files.write("THIS IS NOT VALID SQL;", to: "1_invalid.sql")
            let error = try await #require(throws: DBKitError.self) { try await db.migrate(files.directory) }
            guard case .migrationFailed(let reason) = error else {
                Issue.record("expected DBKitError.migrationFailed, got \(error)")
                return
            }
            #expect(reason.hasPrefix("1_invalid.sql: ") && reason.contains("syntax error"))
        }
    }
}
