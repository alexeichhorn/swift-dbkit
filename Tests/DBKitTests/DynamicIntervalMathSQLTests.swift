import DBKit
import Foundation
import Testing

/// rust-dbkit's `dbkit-core/dynamic_interval_math_sql.rs`, which builds the query of `dynamic_interval_math_support.rs`
/// from hand-made columns and checks parts of its SQL; this compares all of it.
@Suite struct DynamicIntervalMathSQLTests {
    @Test func compilesQueryWithDynamicIntervalMath() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let staleTimeoutSeconds: Int64 = 300
        let retryBaseSeconds = 60.0
        let retryCapSeconds = 3_600.0

        let retryExponent = SQL.least(SQL.greatest(WorkRunModel.attempts - 1, 0), 10)
        let retrySeconds = SQL.least(retryCapSeconds, SQL.power(2.0, retryExponent) * retryBaseSeconds)

        let sql = WorkRunModel.query()
            .filter(
                WorkRunModel.status == "pending"
                    || (WorkRunModel.status == "running" && WorkRunModel.updatedAt <= now - SQL.interval(seconds: staleTimeoutSeconds))
                    || (WorkRunModel.status == "failed" && WorkRunModel.updatedAt <= now - SQL.interval(seconds: retrySeconds))
            )
            .orderBy(WorkRunModel.attempts.asc)
            .orderBy(WorkRunModel.createdAt.asc)
            .forUpdate(.skipLocked)
            .limit(1)
            .render()
            .sql

        #expect(sql == dynamicIntervalMathSQL)
    }
}
