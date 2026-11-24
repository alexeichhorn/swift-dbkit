import DBKit
import Foundation
import Testing

/// rust-dbkit's `dynamic_interval_math_integration.rs`. Its ids are generated; `WorkRunModel` has no
/// `@AutoIncrement`, so these seed them.
@Suite struct DynamicIntervalMathIntegrationTests {
    @Test func queryWithDynamicIntervalMathPrefersLowestAttemptDueRow() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let now = isoDate("2024-04-03T12:00:00Z")

            try await seedRun(on: tx, id: 1, "pending", 5, updatedAt: now - 5, createdAt: now - 30 * 60)
            try await seedRun(on: tx, id: 2, "running", 4, updatedAt: now - 10 * 60, createdAt: now - 40 * 60)
            let failedDue = try await seedRun(on: tx, id: 3, "failed", 3, updatedAt: now - 5 * 60, createdAt: now - 20 * 60)
            try await seedRun(on: tx, id: 4, "failed", 2, updatedAt: now - 90, createdAt: now - 10 * 60)
            try await seedRun(on: tx, id: 5, "running", 0, updatedAt: now - 45, createdAt: now - 15 * 60)

            let claimed = try #require(try await claimQuery(now: now).first(on: tx))
            #expect(claimed.id == failedDue.id)
        }
    }

    @Test func queryWithDynamicIntervalMathMatchesStaleRowsFromIntegerSecondWindows() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let now = isoDate("2024-04-04T09:00:00Z")

            let staleRunning = try await seedRun(on: tx, id: 1, "running", 1, updatedAt: now - 8 * 60, createdAt: now - 20 * 60)
            try await seedRun(on: tx, id: 2, "running", 0, updatedAt: now - 45, createdAt: now - 15 * 60)
            try await seedRun(on: tx, id: 3, "failed", 4, updatedAt: now - 3 * 60, createdAt: now - 10 * 60)

            let claimed = try #require(try await claimQuery(now: now).first(on: tx))
            #expect(claimed.id == staleRunning.id)
        }
    }
}

/// The due run with the fewest attempts, oldest first, locked unless another worker holds it.
private func claimQuery(now: Date) -> Query<WorkRunModel> {
    WorkRunModel.query()
        .filter(dueWindowFilter(now: now, staleTimeoutSeconds: 300, retryBaseSeconds: 60.0, retryCapSeconds: 3_600.0))
        .orderBy(WorkRunModel.attempts.asc)
        .orderBy(WorkRunModel.createdAt.asc)
        .forUpdate(.skipLocked)
        .limit(1)
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        """
        CREATE TEMP TABLE work_runs (
            id BIGINT PRIMARY KEY, status TEXT NOT NULL, attempts INTEGER NOT NULL, updated_at TIMESTAMPTZ NOT NULL,
            created_at TIMESTAMPTZ NOT NULL
        )
        """)
}

@discardableResult
private func seedRun(on tx: Transaction, id: Int64, _ status: String, _ attempts: Int32, updatedAt: Date, createdAt: Date) async throws
    -> WorkRunModel
{
    let run = WorkRunModel.Insert(id: id, status: status, attempts: attempts, updatedAt: updatedAt, createdAt: createdAt)
    return try #require(try await WorkRunModel.insert(run).returningAll().first(on: tx))
}
