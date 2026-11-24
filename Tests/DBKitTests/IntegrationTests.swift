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

/// `sales` as a real table of `streamsReadInBatchesOnEveryExecutor`, which another pooled connection reads.
@Model(table: "streamed_sales")
class StreamedSaleModel {
    @Key @AutoIncrement var id: Int64
    var region: String
    var amount: Int64
    var createdAt: Date
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

/// Teams referenced by a renamed text column other than the primary key. A player names two teams, so each
/// `@HasMany` names its foreign key.
@Model(table: "teams")
class TeamModel {
    @Key @AutoIncrement var id: Int64
    @Unique @ColumnName("code") var handle: String
    var name: String
    @HasMany(key: "teamHandle", references: "handle") var players: [PlayerModel]
    @HasMany(key: "formerTeamHandle", references: "handle") var formerPlayers: [PlayerModel]
}

/// A `UUID` key and two renamed foreign keys, one of them nullable.
@Model(table: "players")
class PlayerModel {
    @Key var id: UUID
    var name: String
    @ColumnName("team_code") var teamHandle: String
    @ColumnName("former_team_code") var formerTeamHandle: String?
    @BelongsTo(key: "teamHandle", references: "handle") var team: TeamModel?
    @BelongsTo(key: "formerTeamHandle", references: "handle") var formerTeam: TeamModel?
    @HasMany var seasons: [RosterEntryModel]
}

/// A composite key with a foreign key in it.
@Model(table: "roster_entries")
class RosterEntryModel {
    @Key var playerID: UUID
    @Key var season: Int32
    var role: String
    @BelongsTo(key: "playerID") var player: PlayerModel?
}

/// Accepts any todo row loaded with its user, whatever else is loaded.
private func ownerName(of todo: TodoModel.WithUser) -> String? {
    todo.user?.name
}

/// Accepts any member row loaded with its organization and manager.
private func summary(of member: MemberModel.WithOrganizationAndManager) -> String {
    "\(member.name), \(member.organization?.name ?? "-"), \(member.manager?.name ?? "-")"
}

/// Accepts any player row loaded with both teams.
private func teamNames(of player: PlayerModel.WithTeamAndFormerTeam) -> [String?] {
    [player.team?.name, player.formerTeam?.name]
}

@Suite struct IntegrationTests {
    @Test func eagerLoadingSelectInJoinedNestedAndExplicit() async throws {
        try await withRollback { tx in
            let (alex, sam) = try await seedTodos(on: tx)

            let users = try await UserModel.query().orderBy(UserModel.id.asc).with(\.todos) { $0.with(\.tags) }.all(on: tx)
            #expect(users.map(\.name) == ["Alex", "Sam"])
            #expect(users[0].todos.map(\.title) == ["Buy milk", "Ship it"])
            #expect(users[0].todos[0].tags.map(\.name) == ["home", "urgent"])
            #expect(users[1].todos.isEmpty)

            let joined = try await UserModel.query().orderBy(UserModel.id.asc).with(\.todos, .joined) { $0.with(\.tags, .joined) }.all(
                on: tx)
            #expect(joined.map(\.name) == ["Alex", "Sam"])
            #expect(Set(joined[0].todos.map(\.title)) == ["Buy milk", "Ship it"])
            #expect(Set(joined[0].todos.flatMap(\.tags).map(\.name)) == ["home", "urgent"])

            // A filter on the joined table also limits the loaded children.
            let filtered = try await UserModel.query().with(\.todos, .joined).filter(TodoModel.title == "Ship it").all(on: tx)
            #expect(filtered.map { $0.todos.map(\.title) } == [["Ship it"]])

            let todos = try await TodoModel.query()
                .filter(TodoModel.Relations.user.name == "Alex")
                .orderBy(TodoModel.id.asc)
                .with(\.user) { $0.with(\.todos) }
                .all(on: tx)
            #expect(todos.count == 2)
            #expect(todos[0].user?.todos.count == 2)

            let loaded = try await sam.load(\.todos, on: tx)
            #expect(loaded.todos.isEmpty)
            let withUser = try #require(try await TodoModel.query().with(\.user).with(\.tags).first(on: tx))
            let plain: TodoModel = withUser
            #expect(plain.id == withUser.id)
            #expect(ownerName(of: withUser) == "Alex")
            #expect(try await UserModel.find(alex.id, on: tx)?.email == "alex@example.com")
        }
    }

    /// Joined rows decode into the tree in the query's order, each parent and child once. Joined and select-in loads
    /// mix on one query and across levels, and a select-in level through a join model keeps a child shared by two
    /// parents once for each.
    @Test func joinedAndSelectInLoadsMixOnOneQueryAndAcrossLevels() async throws {
        try await withRollback { tx in
            _ = try await seedTodos(on: tx)

            let ordered = try await UserModel.query()
                .with(\.todos, .joined) { $0.with(\.tags, .joined) }
                .orderBy(UserModel.id.asc, TodoModel.title.desc, TagModel.name.desc)
                .all(on: tx)
            #expect(ordered.map(\.name) == ["Alex", "Sam"])
            #expect(ordered[0].todos.map(\.title) == ["Ship it", "Buy milk"])
            #expect(ordered[0].todos.map { $0.tags.map(\.name) } == [[], ["urgent", "home"]])
            #expect(ordered[1].todos.isEmpty)

            let selectInTags = try await UserModel.query()
                .orderBy(UserModel.id.asc, TodoModel.id.asc)
                .with(\.todos, .joined) { $0.with(\.tags) }
                .all(on: tx)
            #expect(selectInTags.map { $0.todos.map(\.title) } == [["Buy milk", "Ship it"], []])
            #expect(selectInTags[0].todos.map { $0.tags.map(\.name) } == [["home", "urgent"], []])

            let tags: [TagModel.Loaded<[TodoModel.Loaded<UserModel?, NotLoaded>]>] = try await TagModel.query()
                .orderBy(TagModel.id.asc)
                .with(\.todos) { $0.with(\.user, .joined) }
                .all(on: tx)
            #expect(tags.map { $0.todos.map(\.title) } == [["Buy milk"], ["Buy milk"]])
            #expect(tags.map { $0.todos.map { $0.user?.name } } == [["Alex"], ["Alex"]])

            let todos = try await TodoModel.query().orderBy(TodoModel.id.asc).with(\.tags).with(\.user, .joined).all(on: tx)
            #expect(todos.map { $0.user?.name } == ["Alex", "Alex"])
            #expect(todos.map { $0.tags.map(\.name) } == [["home", "urgent"], []])

            let owners = try await TodoModel.query().orderBy(TodoModel.id.asc).with(\.user, .joined) { $0.with(\.todos) }.all(on: tx)
            #expect(owners.map { $0.user?.todos.map(\.title) } == [["Buy milk", "Ship it"], ["Buy milk", "Ship it"]])
        }
    }

    /// A self-reference loads through aliased joins at every level, and a missing parent stays `nil`.
    @Test func joinedLoadsFollowSelfReferencesAndKeepMissingParents() async throws {
        try await withRollback { tx in
            try await tx.query("CREATE TEMP TABLE organizations (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL)")
            try await tx.query(
                "CREATE TEMP TABLE members (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, organization_id BIGINT NOT NULL, manager_id BIGINT)"
            )
            let acme = try #require(try await OrganizationModel.insert(OrganizationModel.Insert(name: "Acme")).returningAll().first(on: tx))
            let alex = try #require(
                try await MemberModel.insert(MemberModel.Insert(name: "Alex", organizationID: acme.id)).returningAll().first(on: tx))
            let sam = try #require(
                try await MemberModel.insert(MemberModel.Insert(name: "Sam", organizationID: acme.id, managerID: alex.id)).returningAll()
                    .first(on: tx))
            try await MemberModel.insert(MemberModel.Insert(name: "Kim", organizationID: acme.id, managerID: sam.id)).execute(on: tx)

            let chains = try await MemberModel.query()
                .orderBy(MemberModel.id.asc)
                .with(\.organization, .joined)
                .with(\.manager, .joined) { $0.with(\.manager, .joined) }
                .all(on: tx)
            #expect(chains.map(\.name) == ["Alex", "Sam", "Kim"])
            #expect(chains.map { $0.manager?.name } == [nil, "Alex", "Sam"])
            #expect(chains.map { $0.manager?.manager?.name } == [nil, nil, "Alex"])
            #expect(chains.map { $0.organization?.name } == ["Acme", "Acme", "Acme"])
        }
    }

    /// Joins that only filter: a relation joined outer finds rows without children, and a join on another model
    /// takes any condition, also a nullable one.
    @Test func explicitJoinsFilterRowsWithoutLoading() async throws {
        try await withRollback { tx in
            _ = try await seedTodos(on: tx)

            let childless = try await UserModel.query().leftJoin(\.todos).filter(TodoModel.id.isNull).all(on: tx)
            #expect(childless.map(\.name) == ["Sam"])

            let dueToday = try await UserModel.query()
                .join(TodoModel.self, on: TodoModel.userID == UserModel.id && TodoModel.note == "today")
                .all(on: tx)
            #expect(dueToday.map(\.name) == ["Alex"])

            let notDueToday = try await UserModel.query()
                .leftJoin(TodoModel.self, on: TodoModel.userID == UserModel.id && TodoModel.note == "today")
                .filter(TodoModel.id.isNull)
                .all(on: tx)
            #expect(notDueToday.map(\.name) == ["Sam"])
        }
    }

    /// A self-reference through a nullable key, several relations on one query, and loaded rows passed as the plain
    /// model and as `With…` types.
    @Test func selectInLoadsSelfReferencesAndPassesAsWithTypes() async throws {
        try await withRollback { tx in
            try await tx.query("CREATE TEMP TABLE organizations (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL)")
            try await tx.query(
                "CREATE TEMP TABLE members (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, organization_id BIGINT NOT NULL, manager_id BIGINT)"
            )
            let acme = try #require(try await OrganizationModel.insert(OrganizationModel.Insert(name: "Acme")).returningAll().first(on: tx))
            let alex = try #require(
                try await MemberModel.insert(MemberModel.Insert(name: "Alex", organizationID: acme.id)).returningAll().first(on: tx))
            let sam = try #require(
                try await MemberModel.insert(MemberModel.Insert(name: "Sam", organizationID: acme.id, managerID: alex.id)).returningAll()
                    .first(on: tx))
            try await MemberModel.insert(MemberModel.Insert(name: "Kim", organizationID: acme.id, managerID: sam.id)).execute(on: tx)

            let chains = try await MemberModel.query()
                .orderBy(MemberModel.id.asc)
                .with(\.organization)
                .with(\.manager) { $0.with(\.manager) }
                .all(on: tx)
            #expect(chains.map { $0.manager?.name } == [nil, "Alex", "Sam"])
            #expect(chains.map { $0.manager?.manager?.name } == [nil, nil, "Alex"])
            #expect(chains.map { $0.organization?.name } == ["Acme", "Acme", "Acme"])

            let members = try await MemberModel.query().orderBy(MemberModel.id.asc).with(\.manager).with(\.organization).all(on: tx)
            #expect(members.map { summary(of: $0) } == ["Alex, Acme, -", "Sam, Acme, Alex", "Kim, Acme, Sam"])
            let plain: [MemberModel] = members
            #expect(plain.map(\.managerID) == [nil, alex.id, sam.id])
        }
    }

    /// Keys of other types than `Int64`, renamed key columns, a referenced column other than the primary key, a
    /// nullable foreign key and a composite key.
    @Test func selectInLoadsFollowRenamedNullableAndCompositeKeys() async throws {
        try await withRollback { tx in
            try await tx.query("CREATE TEMP TABLE teams (id BIGSERIAL PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL)")
            try await tx.query(
                "CREATE TEMP TABLE players (id UUID PRIMARY KEY, name TEXT NOT NULL, team_code TEXT NOT NULL, former_team_code TEXT)")
            try await tx.query(
                """
                CREATE TEMP TABLE roster_entries (
                    player_id UUID NOT NULL, season INTEGER NOT NULL, role TEXT NOT NULL, PRIMARY KEY (player_id, season)
                )
                """)
            try await TeamModel.insert([
                TeamModel.Insert(handle: "red", name: "Red"),
                TeamModel.Insert(handle: "blue", name: "Blue"),
                TeamModel.Insert(handle: "gray", name: "Gray"),
            ])
            .execute(on: tx)
            let (ana, ben) = (UUID(), UUID())
            try await PlayerModel.insert([
                PlayerModel.Insert(id: ana, name: "Ana", teamHandle: "red"),
                PlayerModel.Insert(id: ben, name: "Ben", teamHandle: "blue", formerTeamHandle: "red"),
            ])
            .execute(on: tx)
            try await RosterEntryModel.insert([
                RosterEntryModel.Insert(playerID: ana, season: 2024, role: "captain"),
                RosterEntryModel.Insert(playerID: ana, season: 2025, role: "keeper"),
                RosterEntryModel.Insert(playerID: ben, season: 2025, role: "wing"),
            ])
            .execute(on: tx)

            let teams = try await TeamModel.query().orderBy(TeamModel.id.asc).with(\.players).with(\.formerPlayers).all(on: tx)
            #expect(teams.map { $0.players.map(\.name) } == [["Ana"], ["Ben"], []])
            #expect(teams.map { $0.formerPlayers.map(\.name) } == [["Ben"], [], []])

            let players = try await PlayerModel.query()
                .orderBy(PlayerModel.name.asc)
                .with(\.team)
                .with(\.formerTeam)
                .with(\.seasons) { $0.with(\.player) }
                .all(on: tx)
            #expect(players.map { teamNames(of: $0) } == [["Red", nil], ["Blue", "Red"]])
            #expect(players.map { $0.seasons.map(\.role).sorted() } == [["captain", "keeper"], ["wing"]])
            #expect(players[0].seasons.allSatisfy { $0.player?.id == ana })

            let entries = try await RosterEntryModel.query()
                .filter(RosterEntryModel.season == 2025)
                .orderBy(RosterEntryModel.role.asc)
                .with(\.player) { $0.with(\.team) }
                .all(on: tx)
            #expect(entries.map { $0.player?.team?.name } == ["Red", "Blue"])
        }
    }

    /// `load(_:on:)` runs one select-in query per relation level, for one row or many, and none for no rows. A loaded
    /// row keeps the relations it has.
    @Test func explicitLoadsRunOneQueryPerLevelAndKeepLoadedRelations() async throws {
        try await withRollback { tx in
            let (alex, sam) = try await seedTodos(on: tx)
            let db = CountingExecutor(base: tx)

            let alexWithTodos: UserModel.Loaded<[TodoModel]> = try await alex.load(\.todos, on: db)
            #expect(alexWithTodos.todos.map(\.title) == ["Buy milk", "Ship it"])
            #expect(await db.counter.count == 1)

            let alexWithTags: UserModel.Loaded<[TodoModel.Loaded<NotLoaded, [TagModel]>]> = try await alex.load(\.todos, on: db) {
                $0.with(\.tags)
            }
            #expect(alexWithTags.todos.map { $0.tags.map(\.name) } == [["home", "urgent"], []])
            #expect(await db.counter.count == 3)

            let usersWithTags = try await [alex, sam].load(\.todos, on: db) { $0.with(\.tags) }
            #expect(usersWithTags.map { $0.todos.map(\.title) } == [["Buy milk", "Ship it"], []])
            #expect(usersWithTags[0].todos.map { $0.tags.map(\.name) } == [["home", "urgent"], []])
            #expect(await db.counter.count == 5)

            let todos = try await TodoModel.query().orderBy(TodoModel.id.asc).all(on: tx)
            let todosWithUser: [TodoModel.Loaded<UserModel?, NotLoaded>] = try await todos.load(\.user, on: db)
            #expect(todosWithUser.map { $0.user?.name } == ["Alex", "Alex"])
            #expect(await db.counter.count == 6)

            let tagged: TodoModel.Loaded<UserModel?, [TagModel]> = try await todosWithUser[0].load(\.tags, on: db)
            #expect(tagged.user?.name == "Alex")
            #expect(tagged.tags.map(\.name) == ["home", "urgent"])
            #expect(await db.counter.count == 7)

            let none: [UserModel.Loaded<[TodoModel]>] = try await [UserModel]().load(\.todos, on: db)
            #expect(none.isEmpty)
            #expect(await db.counter.count == 7)
        }
    }

    /// A to-one relation with a `nil` key loads as `nil`, without a query when no row has a key.
    @Test func explicitLoadsLeaveMissingParentsNil() async throws {
        try await withRollback { tx in
            try await tx.query("CREATE TEMP TABLE organizations (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL)")
            try await tx.query(
                "CREATE TEMP TABLE members (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, organization_id BIGINT NOT NULL, manager_id BIGINT)"
            )
            let acme = try #require(try await OrganizationModel.insert(OrganizationModel.Insert(name: "Acme")).returningAll().first(on: tx))
            let alex = try #require(
                try await MemberModel.insert(MemberModel.Insert(name: "Alex", organizationID: acme.id)).returningAll().first(on: tx))
            let sam = try #require(
                try await MemberModel.insert(MemberModel.Insert(name: "Sam", organizationID: acme.id, managerID: alex.id)).returningAll()
                    .first(on: tx))
            let db = CountingExecutor(base: tx)

            let alexWithManager = try await alex.load(\.manager, on: db)
            #expect(alexWithManager.manager == nil)
            #expect(await db.counter.count == 0)

            let withManagers = try await [alex, sam].load(\.manager, on: db)
            #expect(withManagers.map { $0.manager?.name } == [nil, "Alex"])
            #expect(await db.counter.count == 1)
        }
    }

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

    /// `count`, `exists` and `paginate` count each user or todo once, however the joins multiply or filter rows. See
    /// "Counting a query with joins" in `docs/rust-parity.md`; rust-dbkit counts the joined rows.
    @Test func countExistsAndPaginateCountEachBaseRowOnceAcrossJoins() async throws {
        try await withRollback { tx in
            let (alex, _) = try await seedTodos(on: tx)
            try await TagModel.insert(TagModel.Insert(name: "later")).execute(on: tx)

            // Alex's two todos join him twice.
            let todos: Query<UserModel.Loaded<[TodoModel]>> = UserModel.query().with(\.todos, .joined)
            #expect(try await todos.count(on: tx) == 2)
            #expect(try await TodoModel.query().with(\.user, .joined).count(on: tx) == 2)
            #expect(try await UserModel.query().join(\.todos).count(on: tx) == 1)
            #expect(try await UserModel.query().leftJoin(\.todos).count(on: tx) == 2)
            #expect(try await TodoModel.query().filter(TodoModel.Relations.user.name == "Alex").count(on: tx) == 2)
            // "Buy milk" has two tags.
            #expect(try await TodoModel.query().join(\.tags).count(on: tx) == 1)
            #expect(try await TodoModel.query().with(\.tags, .joined).count(on: tx) == 2)
            // Each of the two tag links joins the two other tags.
            let otherTags = TodoTagModel.query().join(TagModel.self, on: TagModel.id != TodoTagModel.tagID)
            #expect(try await otherTags.count(on: tx) == 2)

            // The kit counted without the join, so PostgreSQL rejected this filter.
            let shipping = todos.filter(TodoModel.title == "Ship it")
            #expect(try await shipping.count(on: tx) == 1)
            #expect(try await shipping.exists(on: tx))
            let nothing = todos.filter(TodoModel.title == "Nothing")
            #expect(try await nothing.count(on: tx) == 0)
            #expect(try await nothing.exists(on: tx) == false)

            let page = try await shipping.orderBy(UserModel.id.asc).paginate(page: 1, perPage: 10, on: tx)
            #expect(page.total == 1 && page.totalPages == 1)
            #expect(page.items.map(\.id) == [alex.id])
            #expect(page.items.first?.todos.map(\.title) == ["Ship it"])
        }
    }

    /// With a joined to-many load, `LIMIT` applies to the joined rows (see "Select-In vs Joined" in
    /// `docs/relations.md`) while `total` counts users: a page of two holds Alex with both todos, and Sam isn't on it.
    @Test func paginateWithAJoinedToManyLoadLimitsJoinedRows() async throws {
        try await withRollback { tx in
            _ = try await seedTodos(on: tx)

            let joined = try await UserModel.query()
                .with(\.todos, .joined)
                .orderBy(UserModel.id.asc)
                .orderBy(TodoModel.id.asc)
                .paginate(page: 1, perPage: 2, on: tx)
            #expect(joined.total == 2 && joined.totalPages == 1)
            #expect(joined.items.map(\.name) == ["Alex"])
            #expect(joined.items.first?.todos.map(\.title) == ["Buy milk", "Ship it"])

            let selectIn = try await UserModel.query().with(\.todos).orderBy(UserModel.id.asc).paginate(page: 1, perPage: 2, on: tx)
            #expect(selectIn.total == 2)
            #expect(selectIn.items.map(\.name) == ["Alex", "Sam"])
        }
    }

    @Test func paginateReadsEachPageAndCountsAllRows() async throws {
        try await withRollback { tx in
            try await createUsers(on: tx)
            try await seedUsers(on: tx)
            let users = UserModel.query().orderBy(UserModel.id.asc)

            let first = try await users.paginate(page: 1, perPage: 2, on: tx)
            #expect(first.items.map(\.name) == ["Alex", "Sam"])
            #expect(first.page == 1 && first.perPage == 2 && first.total == 3 && first.totalPages == 2)
            let last = try await users.paginate(page: 2, perPage: 2, on: tx)
            #expect(last.items.map(\.name) == ["Kim"] && last.totalPages == 2)
            let pastTheEnd = try await users.paginate(page: 3, perPage: 2, on: tx)
            #expect(pastTheEnd.items.isEmpty && pastTheEnd.page == 3 && pastTheEnd.total == 3 && pastTheEnd.totalPages == 2)
            let single = try await users.paginate(page: 3, perPage: 1, on: tx)
            #expect(single.items.map(\.name) == ["Kim"] && single.totalPages == 3)
            let whole = try await users.paginate(page: 1, perPage: 3, on: tx)
            #expect(whole.items.count == 3 && whole.totalPages == 1)

            let empty = try await users.filter(UserModel.region == "mars").paginate(page: 1, perPage: 2, on: tx)
            #expect(empty.items.isEmpty && empty.total == 0 && empty.totalPages == 0)
        }
    }

    /// `paginate` counts without the ordering, then reads the page with it.
    @Test func paginateSendsTheCountAndThenThePage() async throws {
        try await withRollback { tx in
            try await createUsers(on: tx)
            try await seedUsers(on: tx)
            let db = RecordingExecutor(base: tx)

            let page = try await UserModel.query().filter(UserModel.id > 1).orderBy(UserModel.name.asc).paginate(
                page: 2, perPage: 1, on: db)
            #expect(page.items.map(\.name) == ["Sam"] && page.total == 2)
            #expect(
                await db.log.statements == [
                    #"SELECT COUNT(*) FROM (SELECT "users".* FROM "users" WHERE "users"."id" > $1) AS "count""#,
                    #"SELECT "users".* FROM "users" WHERE "users"."id" > $1 ORDER BY "users"."name" ASC LIMIT 1 OFFSET 1"#,
                ])
        }
    }

    /// The query's own `LIMIT` and `OFFSET` apply to `all` only, as in rust-dbkit.
    @Test func countExistsAndPaginateIgnoreTheQuerysOwnLimitAndOffset() async throws {
        try await withRollback { tx in
            try await createUsers(on: tx)
            try await seedUsers(on: tx)
            let skipped = UserModel.query().orderBy(UserModel.id.asc).limit(1).offset(5)

            #expect(try await skipped.all(on: tx).isEmpty)
            #expect(try await skipped.count(on: tx) == 3)
            #expect(try await skipped.exists(on: tx))
            let page = try await skipped.paginate(page: 1, perPage: 2, on: tx)
            #expect(page.items.map(\.name) == ["Alex", "Sam"] && page.total == 3)
        }
    }

    @Test func countAndExistsOfAProjectionCountItsRows() async throws {
        try await withRollback { tx in
            _ = try await seedTodos(on: tx)
            try await UserModel.insert(UserModel.Insert(name: "Kim", email: "kim@example.com", region: "us")).execute(on: tx)

            // Alex and Sam have no region.
            let regions = UserModel.query().select(UserModel.region).groupBy(UserModel.region)
            #expect(try await regions.count(on: tx) == 2)
            #expect(try await regions.filter(UserModel.region == "eu").exists(on: tx) == false)
            // A projection's rows are its joined rows: Alex once per todo.
            #expect(try await UserModel.query().join(\.todos).select(UserModel.name).count(on: tx) == 2)
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
            #expect(try await UserModel.query().count(on: tx) == 2)
            #expect(try await UserModel.query().filter(UserModel.email == "beta@db.com").exists(on: tx))

            let page = try await UserModel.query().orderBy(UserModel.id.asc).paginate(page: 2, perPage: 1, on: tx)
            #expect(page.items.map(\.name) == ["Beta"] && page.total == 2 && page.totalPages == 2)

            var streamed: [String] = []
            for try await user in try await UserModel.query().orderBy(UserModel.id.asc).stream(on: tx) { streamed.append(user.name) }
            #expect(streamed == ["Alpha 2", "Beta"])
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
            #expect(try await HintModel.query().filter(HintModel.note == "changed").count(on: tx) == 1)
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
            #expect(try await RolledBackNoteModel.query().count(on: db) == 0)

            let timeout = try await db.transaction { tx -> String? in
                try await tx.setLocal("statement_timeout", "5s")
                let locked = try await RolledBackNoteModel.query().forUpdate(.skipLocked).all(on: tx)
                #expect(locked.isEmpty)
                return try await tx.query("SHOW statement_timeout").collect().first?.decode(String.self)
            }
            #expect(timeout == "5s")
        }
    }

    /// The name and the value are bind values, so quotes and SQL in them stay data.
    @Test func setLocalSendsTheNameAndValueAsData() async throws {
        let value = "it's'; SET statement_timeout = '1ms'; --"
        try await withRollback { tx in
            try await tx.setLocal("dbkit.test_setting", value)
            #expect(try await tx.query("SELECT current_setting('dbkit.test_setting')").collect().first?.decode(String.self) == value)
        }
        let error = try await #require(throws: PSQLError.self) {
            try await withRollback { tx in try await tx.setLocal("statement_timeout'; --", "5s") }
        }
        #expect(error.serverInfo?[.sqlState] == "42704")
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

    /// The stream's connection is terminated after its first row, so a later fetch fails. A cursor that kept waiting
    /// for an answer on the closed connection would keep the pool's only connection lent, and the last query would wait.
    @Test(.timeLimit(.minutes(1))) func aStreamOnALostConnectionThrowsAndFreesThePool() async throws {
        try await withPoolOfOneConnection { db in
            try await db.query("CREATE TEMP VIEW stream_probe AS SELECT n::BIGINT AS id FROM generate_series(1, 5000) AS n")
            let pid = try #require(try await backendPID(on: db))
            var read = 0
            await #expect(throws: (any Error).self) {
                for try await _ in try await StreamProbeModel.query().stream(on: db) {
                    read += 1
                    guard read == 1 else { continue }
                    // Waits until the backend has exited.
                    let terminated = try await testDatabase().query("SELECT pg_terminate_backend(\(pid), 5000)").collect().first?.decode(
                        Bool.self)
                    #expect(terminated == true)
                }
            }
            #expect(read >= 1 && read < 5000)
            #expect(try await backendPID(on: db) != pid)
        }
    }

    @Test(.timeLimit(.minutes(1))) func streamsReadInBatchesOnEveryExecutor() async throws {
        try await withRealTable(
            "streamed_sales",
            columns: "id BIGSERIAL PRIMARY KEY, region TEXT NOT NULL, amount BIGINT NOT NULL, created_at TIMESTAMPTZ NOT NULL"
        ) { db in
            // 2,500 sales with the amounts 1 to 2,500: more than two stream batches.
            try await db.query(
                "INSERT INTO streamed_sales (region, amount, created_at) SELECT 'r', n, now() FROM generate_series(1, 2500) AS n")
            let sales = StreamedSaleModel.query().orderBy(StreamedSaleModel.amount.asc)

            // 2,000 rows are two full batches, and the bound values travel with the cursor.
            var amounts: [Int64] = []
            for try await sale in try await sales.filter(StreamedSaleModel.amount > 500).filter(StreamedSaleModel.createdAt < Date() + 60)
                .stream(on: db)
            {
                // Another pooled connection answers while the stream holds its own.
                if amounts.isEmpty { #expect(try await StreamedSaleModel.query().count(on: db) == 2500) }
                amounts.append(sale.amount)
            }
            #expect(amounts == Array(501...2500))

            let marked = try await db.transaction { tx in
                var amounts: [Int64] = []
                for try await sale in try await sales.stream(on: tx) { amounts.append(sale.amount) }
                #expect(amounts == Array(1...2500))

                for try await sale in try await sales.stream(on: tx) {
                    // The transaction's connection answers other queries between two rows.
                    try await StreamedSaleModel.update().set(StreamedSaleModel.region, to: "s").filter(StreamedSaleModel.id == sale.id)
                        .execute(on: tx)
                    if sale.amount == 2 { break }
                }
                #expect(try await integer("SELECT count(*) FROM pg_cursors WHERE name <> ''", on: tx) == 0)
                return try await StreamedSaleModel.query().filter(StreamedSaleModel.region == "s").count(on: tx)
            }
            #expect(marked == 2)
            #expect(try await StreamedSaleModel.query().filter(StreamedSaleModel.region == "s").count(on: db) == 2)
        }
    }

    /// `counted_sales` draws from a sequence for every row it produces, so the sequence tells how many rows the server
    /// read. The pool has one connection, so the checks after a stream run on the connection that stream used.
    @Test(.timeLimit(.minutes(1))) func leavingAStreamEarlyStopsTheServerAndFreesTheConnection() async throws {
        try await withPoolOfOneConnection { db in
            try await db.query(
                "CREATE TEMP TABLE sales (id BIGSERIAL PRIMARY KEY, region TEXT NOT NULL, amount BIGINT NOT NULL, created_at TIMESTAMPTZ NOT NULL)"
            )
            try await db.query("INSERT INTO sales (region, amount, created_at) SELECT 'r', n, now() FROM generate_series(1, 2500) AS n")
            try await db.query("CREATE TEMP SEQUENCE sale_reads")
            try await db.query(
                "CREATE TEMP VIEW counted_sales AS SELECT id, amount, nextval('sale_reads') AS read_number FROM sales ORDER BY amount")
            struct Abort: Error {}

            for leave in ["break", "throw", "cancel"] {
                let before = try #require(try await integer("SELECT nextval('sale_reads')", on: db))
                let reader = Task {
                    var amounts: [Int64] = []
                    do {
                        for try await sale in try await CountedSaleModel.query().stream(on: db) {
                            amounts.append(sale.amount)
                            if amounts.count < 2 { continue }
                            if leave == "break" { break }
                            if leave == "throw" { throw Abort() }
                            withUnsafeCurrentTask { $0?.cancel() }
                        }
                    } catch {}
                    return amounts
                }
                #expect(await reader.value == [1, 2], "\(leave)")

                // One batch at most, never the 2,500 rows of the view.
                let produced = try #require(try await integer("SELECT nextval('sale_reads')", on: db)) - before - 1
                #expect(produced >= 2 && produced <= 1000, "\(leave): the server produced \(produced) rows")
                try await expectNoCursorOrTransaction(on: db)
            }

            // The sequence ends after 1,500 numbers, so the second batch fails on the server.
            try await db.query("ALTER SEQUENCE sale_reads RESTART MAXVALUE 1500")
            var read = 0
            await #expect(throws: PSQLError.self) {
                for try await _ in try await CountedSaleModel.query().stream(on: db) { read += 1 }
            }
            #expect(read >= 1000)
            try await expectNoCursorOrTransaction(on: db)
        }
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
                .count(on: tx)
            #expect(masked == 1)

            try await tx.query(
                "CREATE TEMP TABLE sales (id BIGSERIAL PRIMARY KEY, region TEXT NOT NULL, amount BIGINT NOT NULL, created_at TIMESTAMPTZ NOT NULL)"
            )
            try await tx.query(
                "INSERT INTO sales (region, amount, created_at) VALUES ('us', 10, now()), ('us', 5, now()), ('eu', 7, now())")
            struct RegionTotal: Decodable {
                let region: String
                let total: Decimal?
                let saleCount: Int64
            }
            let totals = try await SaleModel.query()
                .select(SaleModel.region.as("region"), SQL.sum(SaleModel.amount).as("total"), SQL.count(SaleModel.id).as("sale_count"))
                .groupBy(SaleModel.region)
                .orderBy(SaleModel.region.asc)
                .all(as: RegionTotal.self, on: tx)
            #expect(totals.map(\.region) == ["eu", "us"] && totals[1].total == 15 && totals[1].saleCount == 2)

            // The same rows through a projection whose columns are named in code.
            @Projection struct RegionCount {
                let region: String
                let saleCount: Int64
                let largest: Int64?
            }
            let counts = try await SaleModel.query()
                .select(
                    RegionCount.columns(region: SaleModel.region, saleCount: SQL.count(SaleModel.id), largest: SQL.max(SaleModel.amount))
                )
                .groupBy(SaleModel.region)
                .orderBy(SaleModel.region.asc)
                .all(on: tx)
            #expect(counts.map(\.region) == ["eu", "us"] && counts[1].saleCount == 2 && counts[1].largest == 10)

            let summary = try await SaleModel.query()
                .select(SQL.count(SaleModel.id), SQL.count(SaleModel.id).filter(SaleModel.region == "us"), SQL.max(SaleModel.amount))
                .first(on: tx)
            #expect(summary?.0 == 3 && summary?.1 == 2 && summary?.2 == 10)

            let text = try await SaleModel.query()
                .select(
                    SQL.concatWithSeparator("-", SaleModel.region, "x"),
                    SQL.regexReplace(SaleModel.region, "u", "U", .global),
                    SQL.splitPart("a,b,c", ",", 2),
                    SaleModel.region.uppercased()
                )
                .filter(SaleModel.region == "us")
                .first(on: tx)
            #expect(text?.0 == "us-x" && text?.1 == "Us" && text?.2 == "b" && text?.3 == "US")
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
            #expect(try await SaleModel.query().filter(SaleModel.createdAt == read.createdAt).count(on: tx) == 1)
            #expect(try await SaleModel.query().filter(SaleModel.createdAt == Expr<Date?>.value(read.createdAt)).count(on: tx) == 1)

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

    /// Each function decodes as its expression type, which is PostgreSQL's: `POWER` is `double precision`, or
    /// `numeric` for `numeric` operands, and `LEAST` and `GREATEST` skip NULL arguments.
    @Test func sqlFunctionsDecodeAsTheirExpressionTypes() async throws {
        try await withRollback { tx in
            try await tx.query(
                """
                CREATE TEMP TABLE prices (
                    id BIGSERIAL PRIMARY KEY, quantity INTEGER NOT NULL, minimum INTEGER, amount NUMERIC NOT NULL, discount NUMERIC,
                    rate DOUBLE PRECISION NOT NULL
                )
                """)
            try await PriceModel.insert(PriceModel.Insert(quantity: 3, minimum: nil, amount: 1.5, discount: nil, rate: 0.5)).execute(on: tx)

            let row: (Double, Decimal, Double?, Int32, Int32?, Decimal, Date) = try #require(
                try await PriceModel.query()
                    .select(
                        SQL.power(PriceModel.quantity, 2),
                        SQL.power(PriceModel.amount, 2),
                        SQL.power(PriceModel.minimum, PriceModel.rate),
                        SQL.greatest(PriceModel.minimum, PriceModel.quantity),
                        SQL.least(PriceModel.minimum, PriceModel.minimum),
                        SQL.coalesce(PriceModel.discount, PriceModel.amount),
                        SQL.dateTrunc(.day, SQL.now())
                    )
                    .first(on: tx))
            let (squared, decimalSquared, nullPower, greatest, least, discount, today) = row
            #expect(squared == 9)
            #expect(decimalSquared == 2.25)
            #expect(nullPower == nil)
            #expect(greatest == 3)
            #expect(least == nil)
            #expect(discount == 1.5)
            #expect(abs(today.timeIntervalSinceNow) < 2 * 86_400)
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

/// Alex with the todos "Buy milk", tagged "home" and "urgent", and "Ship it"; Sam without todos.
private func seedTodos(on tx: Transaction) async throws -> (alex: UserModel, sam: UserModel) {
    try await createUsers(on: tx)
    try await tx.query(
        """
        CREATE TEMP TABLE todos (
            id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL, title TEXT NOT NULL, note TEXT, is_complete BOOLEAN NOT NULL DEFAULT false
        )
        """)
    try await tx.query("CREATE TEMP TABLE tags (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL)")
    try await tx.query("CREATE TEMP TABLE todo_tags (todo_id BIGINT NOT NULL, tag_id BIGINT NOT NULL, PRIMARY KEY (todo_id, tag_id))")

    let users = try await UserModel.insert([
        UserModel.Insert(name: "Alex", email: "alex@example.com"),
        UserModel.Insert(name: "Sam", email: "sam@example.com"),
    ])
    .returningAll().all(on: tx)
    let todos = try await TodoModel.insert([
        TodoModel.Insert(userID: users[0].id, title: "Buy milk"),
        TodoModel.Insert(userID: users[0].id, title: "Ship it", note: "today"),
    ])
    .returningAll().all(on: tx)
    let tags = try await TagModel.insert([TagModel.Insert(name: "home"), TagModel.Insert(name: "urgent")]).returningAll().all(on: tx)
    try await TodoTagModel.insert(tags.map { TodoTagModel.Insert(todoID: todos[0].id, tagID: $0.id) }).execute(on: tx)
    return (users[0], users[1])
}

private func backendPID(on executor: some DatabaseExecutor) async throws -> Int32? {
    try await executor.query("SELECT pg_backend_pid()").collect().first?.decode(Int32.self)
}

private func sleepingBackendPID(on executor: some DatabaseExecutor) async throws -> Int32? {
    try await executor.query("SELECT pg_backend_pid() FROM pg_sleep(0.2)").collect().first?.decode(Int32.self)
}

/// Runs each query on `base` and counts it, to check how many queries a load runs.
private struct CountingExecutor<Base: DatabaseExecutor>: DatabaseExecutor {
    let base: Base
    let counter = QueryCounter()

    var logger: Logger { base.logger }

    func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        await counter.increment()
        return try await base.query(query)
    }
}

private actor QueryCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
