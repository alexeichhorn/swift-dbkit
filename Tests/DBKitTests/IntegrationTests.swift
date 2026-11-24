import DBKit
import Foundation
import ServiceLifecycle
import Testing

@Model(table: "committed_notes")
class CommittedNoteModel {
    @Key @AutoIncrement var id: Int64
    var body: String
}

@Model(table: "rolled_back_notes")
class RolledBackNoteModel {
    @Key @AutoIncrement var id: Int64
    var body: String
}

@Suite struct IntegrationTests {
    @Test func urlsTakeTheLibpqSSLModesAndRejectOthers() throws {
        for mode in ["disable", "allow", "prefer", "require", "verify-ca", "verify-full"] {
            _ = try Database(url: "postgres://app:secret@db.example.com:6543/app?sslmode=\(mode)")
        }
        _ = try Database(url: "postgresql://app@db.example.com/app", connections: 2...4)

        let invalid = [
            ("postgres://app@db.example.com/app?sslmode=bogus", "unsupported sslmode bogus"),
            ("mysql://app@db.example.com/app", "expected postgres://user:password@host:port/database"),
            ("postgres:///app", "expected postgres://user:password@host:port/database"),
            ("postgres://db.example.com/app", "missing user"),
        ]
        for (url, reason) in invalid {
            #expect(throws: DBKitError.invalidDatabaseURL(reason)) { try Database(url: url) }
            #expect(throws: DBKitError.invalidDatabaseURL(reason)) { try PostgresClient.Configuration(url: url) }
        }
        #expect(DBKitError.invalidDatabaseURL("missing user").description == "invalid database URL: missing user")
    }

    @Test func aDatabaseOnItsOwnClientRunsInAServiceGroup() async throws {
        let client = PostgresClient(configuration: try PostgresClient.Configuration(url: testDatabaseURL()))
        let logger = Logger(label: "dbkit-test")
        let db = Database(client: client, logger: logger)
        #expect(db.client === client && db.logger.label == "dbkit-test")

        let services = ServiceGroup(services: [db], logger: logger)
        try await withThrowingDiscardingTaskGroup { tasks in
            tasks.addTask { try await services.run() }
            let answer = try await db.query("SELECT \(41) + 1").collect().first?.decode(Int.self)
            #expect(answer == 42)
            await services.triggerGracefulShutdown()
        }
    }

    /// Both queries sleep, so a pool with a second connection would run them side by side.
    @Test func aPoolOfOneConnectionRunsQueriesOneAfterAnother() async throws {
        let db = try Database(url: testDatabaseURL(), connections: 0...1)
        try await withThrowingDiscardingTaskGroup { tasks in
            tasks.addTask { await db.run() }
            defer { tasks.cancelAll() }
            async let first = sleepingBackendPID(on: db)
            async let second = sleepingBackendPID(on: db)
            let pids = try await (first, second)
            #expect(pids.0 == pids.1)
        }
    }

    @Test func executorsAreInterchangeable() async throws {
        let db = try testDatabase()
        #expect(try await backendPID(on: db) != nil)
        try await withRollback { tx in
            let pid = try await backendPID(on: tx)
            #expect(try await backendPID(on: tx) == pid)
            let viaConnection = try await tx.connection.query("SELECT pg_backend_pid()", logger: tx.logger).collect().first?.decode(
                Int32.self)
            #expect(viaConnection == pid)
        }
    }

    @Test func rawQueriesBindInterpolatedValuesAndDecodeTuples() async throws {
        try await withRollback { tx in
            try await createUsers(on: tx)
            let name = "O'Brien; DROP TABLE users"
            try await tx.query("INSERT INTO users (name, email) VALUES (\(name), \("obrien@example.com"))")

            var rows: [(Int64, String, String?)] = []
            for try await row in try await tx.query("SELECT id, name, region FROM users WHERE name = \(name)").decode(
                (Int64, String, String?).self)
            {
                rows.append(row)
            }
            #expect(rows.count == 1)
            #expect(rows.first?.1 == name && rows.first?.2 == nil)
        }
    }

    @Test func rawQueriesDecodeModelsByColumnName() async throws {
        try await withRollback { tx in
            try await createUsers(on: tx)
            try await seedUsers(on: tx)
            let users = try await tx.query("SELECT region, email, name, id FROM users ORDER BY id", as: UserModel.self)
            #expect(users.map(\.id) == [1, 2, 3])
            #expect(users.map(\.name) == ["Alex", "Sam", "Kim"])
            #expect(users.map(\.email) == ["alex@example.com", "sam@example.com", "kim@example.com"])
            #expect(users.map(\.region) == ["eu", nil, "us"])
            #expect(try await tx.query("SELECT * FROM users WHERE false", as: UserModel.self).isEmpty)
        }
    }

    @Test func allFirstAndFindReadRows() async throws {
        try await withRollback { tx in
            try await createUsers(on: tx)
            try await seedUsers(on: tx)

            let users = try await UserModel.query().orderBy(UserModel.id.asc).all(on: tx)
            #expect(users.map(\.name) == ["Alex", "Sam", "Kim"])
            #expect(users.map(\.region) == ["eu", nil, "us"])
            let page = try await UserModel.query().filter(UserModel.name != "Sam").orderBy(UserModel.name.desc).limit(1).offset(1).all(
                on: tx)
            #expect(page.map(\.name) == ["Alex"])
            #expect(try await UserModel.query().filter(UserModel.email == "nobody@example.com").all(on: tx).isEmpty)

            #expect(try await UserModel.query().orderBy(UserModel.id.desc).first(on: tx)?.name == "Kim")
            #expect(try await UserModel.query().filter(UserModel.email == "nobody@example.com").first(on: tx) == nil)

            #expect(try await UserModel.find(2, on: tx)?.email == "sam@example.com")
            #expect(try await UserModel.find(99, on: tx) == nil)

            // Columns whose names differ from the property: `user_id`, `is_complete`.
            try await tx.query(
                """
                CREATE TEMP TABLE todos (
                    id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL, title TEXT NOT NULL, note TEXT,
                    is_complete BOOLEAN NOT NULL DEFAULT false
                )
                """)
            try await tx.query("INSERT INTO todos (user_id, title, note, is_complete) VALUES (2, 'Ship it', 'today', true)")
            let todo = try #require(try await TodoModel.query().filter(TodoModel.userID == 2).first(on: tx))
            #expect(todo.userID == 2 && todo.title == "Ship it" && todo.note == "today" && todo.isComplete)
        }
    }

    @Test func rowDecodingErrorsNameTheColumn() async throws {
        try await withRollback { tx in
            try await createUsers(on: tx)
            try await seedUsers(on: tx)

            let missing = try await #require(throws: DBKitError.self) {
                try await tx.query("SELECT id, name FROM users", as: UserModel.self)
            }
            #expect(missing == .missingColumn("email"))
            #expect(missing.description == #"result has no column "email""#)

            let mistyped = try await #require(throws: DBKitError.self) {
                try await tx.query("SELECT 'x' AS id, name, email, region FROM users", as: UserModel.self)
            }
            #expect(mistyped == .decodingFailed(column: "id", type: "Int64"))
            #expect(mistyped.description == #"cannot decode column "id" as Int64"#)

            // A table that drifted from the model: `name` became nullable and holds NULL.
            try await tx.query("ALTER TABLE users ALTER COLUMN name DROP NOT NULL")
            try await tx.query("UPDATE users SET name = NULL WHERE id = 2")
            await #expect(throws: DBKitError.decodingFailed(column: "name", type: "String")) {
                try await UserModel.query().all(on: tx)
            }
        }
    }

    @Test func mutationsAndActiveModels() async throws {
        try await withRollback { tx in
            try await createUsers(on: tx)
            let inserted = try await UserModel.insert([
                UserModel.Insert(name: "Alpha", email: "alpha@db.com"),
                UserModel.Insert(name: "Beta", email: "beta@db.com", region: "us"),
            ])
            .execute(on: tx)
            #expect(inserted == 2)
            let ignored = try await UserModel.insert(UserModel.Insert(name: "Dup", email: "alpha@db.com"))
                .onConflictDoNothing(UserModel.email).execute(on: tx)
            #expect(ignored == 0)
            let upserted = try await UserModel.insert(UserModel.Insert(name: "Alpha 2", email: "alpha@db.com"))
                .onConflict(UserModel.email, doUpdate: UserModel.name).returningAll().first(on: tx)
            #expect(upserted?.name == "Alpha 2")
            let alpha = try #require(try await UserModel.query().filter(UserModel.email == "alpha@db.com").first(on: tx))
            var active = alpha.active()
            active.region = "eu"
            let updated = try await active.update(on: tx)
            #expect(updated.region == "eu" && updated.name == alpha.name)

            var draft = ActiveModel<UserModel>()
            draft.name = "Saved"
            draft.email = "saved@db.com"
            let saved = try await draft.save(on: tx)
            #expect(saved.id > 0)

            // Waits for slice 8: `update().set(UserModel.region, to: nil).filter(UserModel.region == "us").execute(on:) == 1`.
            #expect(try await saved.delete(on: tx) == 1)
            // Waits for slice 23: `count(on:) == 2`, `exists(on:)` for beta, `paginate(page: 2, perPage: 1, on:)`.
            // Waits for slice 25: `stream(on:)` yields "Alpha 2" and "Beta".
        }
    }

    @Test func mutationsCountAffectedRowsAndReturnDeletedRows() async throws {
        try await withRollback { tx in
            try await createUsers(on: tx)
            try await seedUsers(on: tx)
            #expect(try await UserModel.update().set(UserModel.region, to: "apac").filter(UserModel.id >= 2).execute(on: tx) == 2)
            #expect(try await UserModel.update().set(UserModel.name, to: "Nobody").filter(UserModel.id == 99).execute(on: tx) == 0)
            // An empty insert sends no statement, since `INSERT … VALUES` needs a row.
            #expect(try await UserModel.insert([]).execute(on: tx) == 0)

            let deleted = try await UserModel.delete().filter(UserModel.region == "apac").returningAll().all(on: tx)
            #expect(deleted.map(\.name).sorted() == ["Kim", "Sam"])
            #expect(try await UserModel.query().all(on: tx).map(\.name) == ["Alex"])
        }
    }

    @Test func anActiveUpdateOfADeletedRowThrowsRowNotFound() async throws {
        try await withRollback { tx in
            try await createUsers(on: tx)
            try await seedUsers(on: tx)
            let user = try #require(try await UserModel.find(1, on: tx))
            try await user.delete(on: tx)

            var active = user.active()
            active.name = "Gone"
            let error = try await #require(throws: DBKitError.self) { try await active.save(on: tx) }
            #expect(error == .rowNotFound)
            #expect(error.description == "no row matches the primary key")
        }
    }

    /// `hints` has no primary key constraint, which would forbid the NULL; the model's key still names both columns.
    @Test func aRowWhoseKeyHasANullColumnIsUpdatedAndDeleted() async throws {
        try await withRollback { tx in
            try await tx.query("CREATE TEMP TABLE hints (name TEXT NOT NULL, region TEXT, note TEXT NOT NULL)")
            try await HintModel.insert([
                HintModel.Insert(name: "a", note: "target"),
                HintModel.Insert(name: "a", region: "eu", note: "same name"),
                HintModel.Insert(name: "b", note: "same region"),
            ])
            .execute(on: tx)
            let row = try #require(try await HintModel.query().filter(HintModel.note == "target").first(on: tx))
            #expect(row.name == "a" && row.region == nil)

            var active = row.active()
            active.note = "changed"
            #expect(try await active.update(on: tx).note == "changed")
            #expect(try await HintModel.query().filter(HintModel.note == "changed").all(on: tx).count == 1)
            #expect(try await row.delete(on: tx) == 1)
            #expect(try await HintModel.query().orderBy(HintModel.name.asc).all(on: tx).map(\.note) == ["same name", "same region"])
        }
    }

    @Test func transactionsCommitWhenTheBodyReturns() async throws {
        try await withRealTable("committed_notes", columns: "id BIGSERIAL PRIMARY KEY, body TEXT NOT NULL") { db in
            let id = try await db.transaction { tx in
                try await tx.query("INSERT INTO committed_notes (body) VALUES ('kept') RETURNING id").collect().first?.decode(
                    Int64.self)
            }
            let committed = try #require(id)
            #expect(try await CommittedNoteModel.find(committed, on: db)?.body == "kept")
        }
    }

    @Test func transactionsRollBackAndScopeSettings() async throws {
        try await withRealTable("rolled_back_notes", columns: "id BIGSERIAL PRIMARY KEY, body TEXT NOT NULL") { db in
            struct Abort: Error {}
            await #expect(throws: Abort.self) {
                try await db.transaction { tx in
                    try await tx.query("INSERT INTO rolled_back_notes (body) VALUES ('ghost')")
                    #expect(try await RolledBackNoteModel.query().all(on: tx).map(\.body) == ["ghost"])
                    throw Abort()
                }
            }
            let notes = try await RolledBackNoteModel.query().all(on: db)
            #expect(notes.isEmpty)
            // Waits for slice 24: `tx.setLocal("statement_timeout", "5s")`, read back with `SHOW statement_timeout`.
            // Waits for slice 22: `UserModel.query().forUpdate(.skipLocked).all(on: tx)` in that transaction.
        }
    }

    /// PostgresNIO never answers a query sent on a closed connection, so without a check these wait forever.
    @Test func queriesOnALostConnectionThrow() async throws {
        let db = try testDatabase()
        // Waits for slice 28: the same on a dedicated connection, for `ping()`, `AdvisoryLock.tryAcquire` and `query`.
        let error = try await #require(throws: DBKitError.self) {
            try await db.transaction { tx in
                let pid = try await tx.query("SELECT pg_backend_pid()").collect().first?.decode(Int32.self)
                try await db.query("SELECT pg_terminate_backend(\(pid))")
                try await Task.sleep(for: .milliseconds(100))
                try await tx.query("SELECT 1")
            }
        }
        #expect(error == .connectionClosed)
        #expect(error.description == "the connection is closed")
        // The pool replaces the lost connection.
        #expect(try await db.query("SELECT 1").collect().count == 1)
    }
}

/// `users` as a temp table, which shadows a real table of that name until the transaction ends.
private func createUsers(on tx: Transaction) async throws {
    try await tx.query("CREATE TEMP TABLE users (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE, region TEXT)")
}

/// Alex (1, eu), Sam (2, no region) and Kim (3, us).
private func seedUsers(on tx: Transaction) async throws {
    try await tx.query(
        "INSERT INTO users (name, email, region) VALUES ('Alex', 'alex@example.com', 'eu'), ('Sam', 'sam@example.com', NULL), ('Kim', 'kim@example.com', 'us')"
    )
}

private func backendPID(on executor: some DatabaseExecutor) async throws -> Int32? {
    try await executor.query("SELECT pg_backend_pid()").collect().first?.decode(Int32.self)
}

private func sleepingBackendPID(on executor: some DatabaseExecutor) async throws -> Int32? {
    try await executor.query("SELECT pg_backend_pid() FROM pg_sleep(0.2)").collect().first?.decode(Int32.self)
}
