import DBKit
import Testing

/// Stops at the first query and reports its SQL, so no database is needed.
private struct CaptureExecutor: DatabaseExecutor {
    struct Captured: Error {
        let sql: String
    }

    let logger = Logger(label: "capture")

    func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        throw Captured(sql: query.sql)
    }
}

@Suite struct OneLimitTests {
    @Test func oneAppliesLimitOne() async throws {
        let captured = try await #require(throws: CaptureExecutor.Captured.self) {
            try await UserModel.query().first(on: CaptureExecutor())
        }
        #expect(captured.sql == #"SELECT "users".* FROM "users" LIMIT 1"#)
    }
}
