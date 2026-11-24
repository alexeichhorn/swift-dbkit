import Foundation
import PostgresNIO

extension Database {
    /// Applies the pending SQL migrations in `directory`, like sqlx's migrator in rust-dbkit.
    ///
    /// Files are named `<version>_<name>.sql` (e.g. `0001_create_users.sql`) and applied in version order, each in its
    /// own transaction. `_dbkit_migrations` records every applied version with a checksum, so a run fails when an
    /// applied file was edited or deleted: migrations are forward-only, fix mistakes with a new file. An advisory lock
    /// makes replicas that start together apply them once.
    public func migrate(_ directory: URL) async throws {
        let migrations = try Migration.load(from: directory)
        try await client.withConnection { connection in
            _ = try await connection.query("SELECT pg_advisory_lock(\(Migration.lockID))", logger: logger).collect()
            do {
                try await applyPending(migrations, on: connection)
            } catch {
                _ = try? await connection.query("SELECT pg_advisory_unlock(\(Migration.lockID))", logger: logger).collect()
                throw error
            }
            _ = try await connection.query("SELECT pg_advisory_unlock(\(Migration.lockID))", logger: logger).collect()
        }
    }

    private func applyPending(_ migrations: [Migration], on connection: PostgresConnection) async throws {
        try await connection.query(
            """
            CREATE TABLE IF NOT EXISTS _dbkit_migrations (
                version BIGINT PRIMARY KEY,
                name TEXT NOT NULL,
                checksum BIGINT NOT NULL,
                applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """, logger: logger)
        var appliedChecksums: [Int64: Int64] = [:]
        let rows = try await connection.query("SELECT version, checksum FROM _dbkit_migrations", logger: logger)
        for try await (version, checksum) in rows.decode((Int64, Int64).self) {
            appliedChecksums[version] = checksum
        }

        let versions = Set(migrations.map(\.version))
        if let missing = appliedChecksums.keys.sorted().first(where: { !versions.contains($0) }) {
            throw DBKitError.migrationFailed("version \(missing) is applied, but its file is missing")
        }
        for migration in migrations {
            if let checksum = appliedChecksums[migration.version] {
                guard checksum == migration.checksum else {
                    throw DBKitError.migrationFailed("\(migration.name).sql changed after it was applied; add a new migration instead")
                }
                continue
            }
            logger.info("applying migration", metadata: ["migration": "\(migration.name)"])
            try await connection.query("BEGIN", logger: logger)
            do {
                for statement in migration.statements {
                    try await connection.query(PostgresQuery(unsafeSQL: statement), logger: logger)
                }
                try await connection.query(
                    """
                    INSERT INTO _dbkit_migrations (version, name, checksum)
                    VALUES (\(migration.version), \(migration.name), \(migration.checksum))
                    """, logger: logger)
                try await connection.query("COMMIT", logger: logger)
            } catch {
                _ = try? await connection.query("ROLLBACK", logger: logger)
                // PSQLError's description hides the server message; the debug description has it.
                throw DBKitError.migrationFailed("\(migration.name).sql: \(String(reflecting: error))")
            }
        }
    }
}

/// One `<version>_<name>.sql` file.
struct Migration {
    /// Arbitrary constant shared by every process that migrates the same database.
    static let lockID: Int64 = 0x6462_6B69_745F_6D67

    let version: Int64
    /// The file name without `.sql`.
    let name: String
    let sql: String

    /// FNV-1a of the file. Detects edits, not tampering.
    var checksum: Int64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in sql.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return Int64(bitPattern: hash)
    }

    /// PostgresNIO sends every query as a prepared statement, which holds one command, so the file is split at
    /// top-level semicolons. Semicolons in quotes, escape strings (`E'…'`), dollar quotes (function bodies) and
    /// comments don't split.
    var statements: [String] {
        let bytes = Array(sql.utf8)
        var statements: [String] = []
        var start = 0
        var index = 0
        var hasCode = false

        func end(after terminator: some Collection<UInt8>, from position: Int) -> Int {
            var position = position
            while position + terminator.count <= bytes.count {
                if bytes[position..<position + terminator.count].elementsEqual(terminator) { return position + terminator.count }
                position += 1
            }
            return bytes.count
        }

        /// Whether the quote at `position` opens an escape string, `E'…'`. The `E` has to stand on its own, not at
        /// the end of a name.
        func opensEscapeString(at position: Int) -> Bool {
            guard position > 0, bytes[position - 1] | 0x20 == UInt8(ascii: "e") else { return false }
            guard position > 1 else { return true }
            let before = Character(Unicode.Scalar(bytes[position - 2]))
            return !(before.isLetter || before.isNumber || before == "_" || !before.isASCII)
        }

        /// The end of the escape string whose text starts at `position`: a backslash escapes the next character, and
        /// a doubled quote is a quote in the text.
        func endOfEscapeString(from position: Int) -> Int {
            var position = position
            while position < bytes.count {
                if bytes[position] == UInt8(ascii: "\\") {
                    position += 2
                } else if bytes[position] != UInt8(ascii: "'") {
                    position += 1
                } else if position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "'") {
                    position += 2
                } else {
                    return position + 1
                }
            }
            return bytes.count
        }

        while index < bytes.count {
            let byte = bytes[index]
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            switch byte {
            case UInt8(ascii: "-") where next == UInt8(ascii: "-"):
                index = end(after: [UInt8(ascii: "\n")], from: index)
            case UInt8(ascii: "/") where next == UInt8(ascii: "*"):
                index = end(after: "*/".utf8, from: index + 2)
            case UInt8(ascii: "'") where opensEscapeString(at: index):
                hasCode = true
                index = endOfEscapeString(from: index + 1)
            case UInt8(ascii: "'"), UInt8(ascii: "\""):
                // A doubled quote inside closes and reopens, which ends up in the same place.
                hasCode = true
                index = end(after: [byte], from: index + 1)
            case UInt8(ascii: "$"):
                hasCode = true
                let tag = Self.dollarQuoteTag(in: bytes, at: index)
                index = tag.map { end(after: $0, from: index + $0.count) } ?? index + 1
            case UInt8(ascii: ";"):
                if hasCode { statements.append(String(decoding: bytes[start..<index], as: UTF8.self)) }
                start = index + 1
                hasCode = false
                index += 1
            default:
                if !Character(Unicode.Scalar(byte)).isWhitespace { hasCode = true }
                index += 1
            }
        }
        if hasCode { statements.append(String(decoding: bytes[start...], as: UTF8.self)) }
        return statements
    }

    /// The `$tag$` or `$$` opening a dollar-quoted string at `index`; nil for parameters like `$1`.
    private static func dollarQuoteTag(in bytes: [UInt8], at index: Int) -> ArraySlice<UInt8>? {
        var end = index + 1
        while end < bytes.count {
            let byte = bytes[end]
            let isLetter = (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte | 0x20) || byte == UInt8(ascii: "_")
            let isDigit = (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            guard isLetter || (isDigit && end > index + 1) else { break }
            end += 1
        }
        guard end < bytes.count, bytes[end] == UInt8(ascii: "$") else { return nil }
        return bytes[index...end]
    }

    static func load(from directory: URL) throws -> [Migration] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var migrations: [Migration] = []
        for file in files where file.pathExtension == "sql" {
            let name = file.deletingPathExtension().lastPathComponent
            guard let separator = name.firstIndex(of: "_"), let version = Int64(name[..<separator]) else {
                throw DBKitError.migrationFailed("\(name).sql must be named <version>_<name>.sql, e.g. 0001_create_users.sql")
            }
            if let duplicate = migrations.first(where: { $0.version == version }) {
                throw DBKitError.migrationFailed("\(name).sql and \(duplicate.name).sql share version \(version)")
            }
            migrations.append(Migration(version: version, name: name, sql: try String(contentsOf: file, encoding: .utf8)))
        }
        return migrations.sorted { $0.version < $1.version }
    }
}
