import DBKit
import Testing

@Suite struct LocalSettingsTests {
    /// A pool of one connection, so the query after the transaction runs on the connection that held the setting.
    @Test func setLocalSetsTransactionScopedPostgresSetting() async throws {
        let db = try Database(url: testDatabaseURL(), connections: 0...1)
        try await withThrowingDiscardingTaskGroup { tasks in
            tasks.addTask { await db.run() }
            defer { tasks.cancelAll() }
            let pid = try await db.transaction { tx in
                try await tx.setLocal("dbkit.test_setting", "1000")
                #expect(try await currentTestSetting(on: tx) == "1000")
                return try await tx.query("SELECT pg_backend_pid()").collect().first?.decode(Int32.self)
            }
            #expect(try await db.query("SELECT pg_backend_pid()").collect().first?.decode(Int32.self) == pid)
            #expect(try await currentTestSetting(on: db) != "1000")
        }
    }
}

private func currentTestSetting(on executor: some DatabaseExecutor) async throws -> String? {
    try await executor.query("SELECT current_setting('dbkit.test_setting', true)").collect().first?.decode(String?.self)
}
