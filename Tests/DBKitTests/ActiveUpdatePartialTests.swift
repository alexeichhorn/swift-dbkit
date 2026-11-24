import DBKit
import Synchronization
import Testing

@Suite struct ActiveUpdatePartialTests {
    @Test func activeUpdateOnlySetsChangedFields() async {
        let executor = CaptureExecutor()
        var active = UserModel(id: 1, name: "Old", email: "old@db.com").active()
        active.name = "New"

        _ = try? await active.update(on: executor)

        #expect(executor.sql == [#"UPDATE "users" SET "name" = $1 WHERE "users"."id" = $2 RETURNING *"#])
    }

    @Test func activeUpdateNoChangesSkipsSQL() async throws {
        let executor = CaptureExecutor()
        let active = UserModel(id: 1, name: "Old", email: "old@db.com").active()

        // rust-dbkit returns an error here; see `docs/rust-parity.md`.
        let unchanged = try await active.update(on: executor)
        #expect(unchanged.id == 1 && unchanged.name == "Old" && unchanged.email == "old@db.com")
        #expect(executor.sql.isEmpty, "update should not execute SQL")
    }
}

/// Records the SQL of each query and fails it, since no database is behind it.
private final class CaptureExecutor: DatabaseExecutor {
    let logger = Logger(label: "capture")
    private let captured = Mutex<[String]>([])

    var sql: [String] { captured.withLock { $0 } }

    func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        captured.withLock { $0.append(query.sql) }
        throw NoDatabase()
    }
}

private struct NoDatabase: Error {}
