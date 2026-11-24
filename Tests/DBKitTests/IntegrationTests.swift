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

/// A type of the app's own, stored as `text` through its PostgresNIO encoding.
struct EmailAddress: SQLValue, Equatable {
    static var sqlTypeName: String { "text" }
    static var psqlType: PostgresDataType { .text }
    static var psqlFormat: PostgresFormat { .binary }

    let address: String

    init(_ address: String) {
        self.address = address
    }

    func encode<JSONEncoder: PostgresJSONEncoder>(into byteBuffer: inout ByteBuffer, context: PostgresEncodingContext<JSONEncoder>) {
        byteBuffer.writeString(address)
    }

    init<JSONDecoder: PostgresJSONDecoder>(
        from buffer: inout ByteBuffer, type: PostgresDataType, format: PostgresFormat, context: PostgresDecodingContext<JSONDecoder>
    ) throws {
        address = try String(from: &buffer, type: type, format: format, context: context)
    }
}

/// A column of each value type that neither rust-dbkit nor the kit tests, and the nullable form of a few.
@Model(table: "value_rows")
class ValueRowModel {
    @Key @AutoIncrement var id: Int64
    var price: Decimal
    var ratio: Float
    var score: Double
    var flags: [Bool]
    var smallCounts: [Int16]
    var counts: [Int32]
    var bigCounts: [Int64]
    var sizes: [Int]
    var ratios: [Float]
    var scores: [Double]
    var ids: [UUID]
    var dates: [Date]
    var email: EmailAddress
    var discount: Decimal?
    var weights: [Double]?
    var backupEmail: EmailAddress?
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

    /// A `Decodable` type matches each property to the alias of the same name or of its snake_case form, and fails on a
    /// property without a column. A comparison on a nullable column decodes as `Bool?`, `nil` where the column is NULL.
    @Test func projectionsDecodeByAliasAndNullableComparisonsAsOptionals() async throws {
        struct Contact: Decodable, Equatable {
            let name: String
            let emailAddress: String
            let isUS: Bool?
        }

        try await withRollback { tx in
            try await createUsers(on: tx)
            try await seedUsers(on: tx)

            let contacts = try await UserModel.query()
                .select(UserModel.name.as("name"), UserModel.email.as("email_address"), (UserModel.region == "us").as("isUS"))
                .orderBy(UserModel.id.asc)
                .all(as: Contact.self, on: tx)
            #expect(
                contacts == [
                    Contact(name: "Alex", emailAddress: "alex@example.com", isUS: false),
                    Contact(name: "Sam", emailAddress: "sam@example.com", isUS: nil),
                    Contact(name: "Kim", emailAddress: "kim@example.com", isUS: true),
                ])

            let missing = try await #require(throws: DBKitError.self) {
                try await UserModel.query().select(UserModel.name.as("name")).first(as: Contact.self, on: tx)
            }
            #expect(missing == .missingColumn("emailAddress"))

            let isUS: [Bool?] = try await UserModel.query().select(UserModel.region == "us").orderBy(UserModel.id.asc).all(on: tx)
            #expect(isUS == [false, nil, true])

            let withoutRegion: [Bool] = try await UserModel.query()
                .select(UserModel.region.isNull)
                .distinct()
                .orderBy(UserModel.region.isNull.asc)
                .all(on: tx)
            #expect(withoutRegion == [false, true])
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

            let renamed = try await UserModel.update().set(UserModel.region, to: nil).filter(UserModel.region == "us").execute(on: tx)
            #expect(renamed == 1)
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
            let nullRegion = try await HintModel.query().filter(HintModel.name == "a").filter(HintModel.region == nil).all(on: tx)
            #expect(nullRegion.map(\.note) == ["target"])

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

    @Test func postgresTypesAggregatesAndFunctions() async throws {
        try await withRollback { tx in
            try await tx.query(
                """
                CREATE TEMP TABLE documents (
                    id BIGSERIAL PRIMARY KEY, type TEXT NOT NULL, tags TEXT[] NOT NULL, scores BIGINT[] NOT NULL, preferences JSONB,
                    payload BYTEA NOT NULL, access_mask BIGINT NOT NULL, lease_window INTERVAL NOT NULL
                )
                """)
            let document = try await DocumentModel.insert(
                DocumentModel.Insert(
                    kind: "note",
                    tags: ["a", "b"],
                    scores: [1, 2],
                    preferences: Preferences(theme: "dark"),
                    payload: Data([0, 1, 2]),
                    accessMask: 0b0110,
                    leaseWindow: .hours(2)
                )
            ).returningAll().first(on: tx)
            #expect(
                document?.preferences == Preferences(theme: "dark") && document?.tags == ["a", "b"] && document?.payload == Data([0, 1, 2]))
            let masked = try await DocumentModel.query()
                .filter((DocumentModel.accessMask & 0b0010) != 0)
                .filter(SQL.interval(hours: 2) == DocumentModel.leaseWindow)
                .filter(DocumentModel.kind == "note")
                .all(on: tx)
            #expect(masked.count == 1)

            // Waits for slice 14b: the `sales` totals per region, as `Decodable` rows, as a `@Projection` and as a tuple.
            // Waits for slice 16: the string functions on `sales`.
            // Waits for slices 26 and 28: the `tasks` insert with `@DatabaseDefault var updatedAt: Date`, the enum update,
            // `SQL.row(TaskModel.state, TaskModel.title).in(…)` over the enum column, and `deliveries`.
        }
    }

    /// A timestamp read from a row must be written back unchanged; these two lose a microsecond when truncated.
    @Test(arguments: ["2017-07-07 04:49:25.453571", "2034-03-02 03:02:14.249081"])
    func datesBindToTheNearestMicrosecond(stored: String) async throws {
        try await withRollback { tx in
            try await tx.query(
                "CREATE TEMP TABLE sales (id BIGSERIAL PRIMARY KEY, region TEXT NOT NULL, amount BIGINT NOT NULL, created_at TIMESTAMPTZ NOT NULL)"
            )
            try await tx.query("INSERT INTO sales (region, amount, created_at) VALUES ('read', 1, \(stored + "+00")::timestamptz)")
            let read = try #require(try await SaleModel.query().first(on: tx))
            #expect(try await SaleModel.query().filter(SaleModel.createdAt == read.createdAt).all(on: tx).count == 1)
            #expect(try await SaleModel.query().filter(SaleModel.createdAt == Expr<Date?>.value(read.createdAt)).all(on: tx).count == 1)

            var active = read.active()
            active.createdAt = read.createdAt
            _ = try await active.update(on: tx)
            try await SaleModel.insert(SaleModel.Insert(region: "inserted", amount: 1, createdAt: read.createdAt)).execute(on: tx)
            try await SaleModel.insert(SaleModel.Insert(region: "set", amount: 1, createdAt: Date(timeIntervalSince1970: 0))).execute(
                on: tx)
            try await SaleModel.update().set(SaleModel.createdAt, to: read.createdAt).filter(SaleModel.region == "set").execute(on: tx)

            var written: [String] = []
            let rows = try await tx.query(
                "SELECT to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') FROM sales ORDER BY id")
            for try await text in rows.decode(String.self) { written.append(text) }
            #expect(written == [stored, stored, stored])
        }
    }

    /// PostgreSQL rejects a comparison inside another one unless it is parenthesized.
    @Test func comparisonsOfComparisonsRun() async throws {
        try await withRollback { tx in
            try await tx.query(
                """
                CREATE TEMP TABLE todos (
                    id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL, title TEXT NOT NULL, note TEXT,
                    is_complete BOOLEAN NOT NULL DEFAULT false
                )
                """)
            try await TodoModel.insert([
                TodoModel.Insert(userID: 1, title: "open, first user", isComplete: false),
                TodoModel.Insert(userID: 2, title: "done, second user", isComplete: true),
                TodoModel.Insert(userID: 2, title: "open, second user", isComplete: false),
                TodoModel.Insert(userID: 1, title: "done, first user", isComplete: true),
            ])
            .execute(on: tx)

            let matching = try await TodoModel.query()
                .filter(TodoModel.isComplete == (TodoModel.userID > 1))
                .orderBy(TodoModel.id.asc)
                .all(on: tx)
            #expect(matching.map(\.title) == ["open, first user", "done, second user"])

            let mismatching = try await TodoModel.query()
                .filter((TodoModel.userID > 1).isDistinct(from: TodoModel.isComplete))
                .orderBy(TodoModel.id.asc)
                .all(on: tx)
            #expect(mismatching.map(\.title) == ["open, second user", "done, first user"])
        }
    }

    @Test func valueTypesRoundtripThroughInsertsFiltersAndUpdates() async throws {
        try await withRollback { tx in
            try await tx.query(
                """
                CREATE TEMP TABLE value_rows (
                    id BIGSERIAL PRIMARY KEY, price NUMERIC NOT NULL, ratio REAL NOT NULL, score DOUBLE PRECISION NOT NULL,
                    flags BOOLEAN[] NOT NULL, small_counts SMALLINT[] NOT NULL, counts INTEGER[] NOT NULL, big_counts BIGINT[] NOT NULL,
                    sizes BIGINT[] NOT NULL, ratios REAL[] NOT NULL, scores DOUBLE PRECISION[] NOT NULL, ids UUID[] NOT NULL,
                    dates TIMESTAMPTZ[] NOT NULL, email TEXT NOT NULL, discount NUMERIC, weights DOUBLE PRECISION[], backup_email TEXT
                )
                """)
            let price = Decimal(string: "12.34")!
            let discount = Decimal(string: "0.5")!
            let ids = [
                UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            ]
            let dates = [isoDate("2024-01-02T03:04:05Z"), isoDate("2024-03-14T10:15:00Z")]

            let inserted = try #require(
                try await ValueRowModel.insert(
                    ValueRowModel.Insert(
                        price: price, ratio: 0.5, score: 2.25, flags: [true, false], smallCounts: [1, -2], counts: [3, 4],
                        bigCounts: [5, 6],
                        sizes: [7, 8], ratios: [0.25, 0.75], scores: [1.5, -1.5], ids: ids, dates: dates, email: EmailAddress("a@b.com"),
                        discount: discount, weights: [0.1, 0.2], backupEmail: EmailAddress("b@c.com"))
                )
                .returningAll().first(on: tx))
            #expect(inserted.price == price && inserted.ratio == 0.5 && inserted.score == 2.25)
            #expect(inserted.flags == [true, false] && inserted.smallCounts == [1, -2] && inserted.counts == [3, 4])
            #expect(inserted.bigCounts == [5, 6] && inserted.sizes == [7, 8] && inserted.ratios == [0.25, 0.75])
            #expect(inserted.scores == [1.5, -1.5] && inserted.ids == ids && inserted.dates == dates)
            #expect(inserted.email == EmailAddress("a@b.com") && inserted.discount == discount)
            #expect(inserted.weights == [0.1, 0.2] && inserted.backupEmail == EmailAddress("b@c.com"))

            let matched = try await ValueRowModel.query()
                .filter(ValueRowModel.price == price)
                .filter(ValueRowModel.ratio == 0.5)
                .filter(ValueRowModel.score > 2)
                .filter(ValueRowModel.ids == ids)
                .filter(ValueRowModel.dates == dates)
                .filter(ValueRowModel.email == EmailAddress("a@b.com"))
                .filter(ValueRowModel.discount == discount)
                .all(on: tx)
            #expect(matched.map(\.id) == [inserted.id])

            let updated = try #require(
                try await ValueRowModel.update()
                    .set(ValueRowModel.price, to: Decimal(string: "99.99")!)
                    .set(ValueRowModel.ids, to: [])
                    .set(ValueRowModel.weights, to: [3])
                    .set(ValueRowModel.backupEmail, to: EmailAddress("c@d.com"))
                    .filter(ValueRowModel.id == inserted.id)
                    .returningAll()
                    .first(on: tx))
            #expect(updated.price == Decimal(string: "99.99") && updated.ids.isEmpty)
            #expect(updated.weights == [3] && updated.backupEmail == EmailAddress("c@d.com"))
        }
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
