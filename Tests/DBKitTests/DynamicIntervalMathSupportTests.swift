import DBKit
import Foundation
import Testing

/// rust-dbkit's `work_runs` of `dynamic_interval_math_support.rs`. `Date` stands in for its `timestamp` columns.
@Model(table: "work_runs")
class WorkRunModel {
    @Key var id: Int64
    var status: String
    var attempts: Int32
    var updatedAt: Date
    var createdAt: Date
}

@Suite struct DynamicIntervalMathSupportTests {
    /// The annotations fail to compile when a result type changes.
    @Test func dynamicIntervalMathAPIPreservesExpectedExpressionTypes() {
        let retryExponent: Expr<Int32> = SQL.least(SQL.greatest(WorkRunModel.attempts - 1, 0), 10)
        let retrySeconds: Expr<Double> = SQL.power(2.0, retryExponent) * 60.0
        let _: Expr<Interval> = SQL.interval(seconds: Int64(300))
        let _: Expr<Interval> = SQL.interval(seconds: retrySeconds)
    }

    /// rust-dbkit checks parts of the SQL; this compares all of it.
    @Test func queryWithDynamicIntervalMathHasExpectedSQLShape() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sql = WorkRunModel.query()
            .filter(dueWindowFilter(now: now, staleTimeoutSeconds: 300, retryBaseSeconds: 60.0, retryCapSeconds: 3_600.0))
            .orderBy(WorkRunModel.attempts.asc)
            .orderBy(WorkRunModel.createdAt.asc)
            .forUpdate(.skipLocked)
            .limit(1)
            .render()
            .sql
        #expect(sql == dynamicIntervalMathSQL)
    }
}

/// The runs a worker may claim at `now`: pending ones, running ones not updated for `staleTimeoutSeconds`, and failed
/// ones whose retry delay has passed, which doubles with each attempt from `retryBaseSeconds` up to `retryCapSeconds`.
func dueWindowFilter(now: Date, staleTimeoutSeconds: Int64, retryBaseSeconds: Double, retryCapSeconds: Double) -> Expr<Bool> {
    let retryExponent: Expr<Int32> = SQL.least(SQL.greatest(WorkRunModel.attempts - 1, 0), 10)
    let retrySeconds: Expr<Double> = SQL.least(retryCapSeconds, SQL.power(2.0, retryExponent) * retryBaseSeconds)
    return WorkRunModel.status == "pending"
        || (WorkRunModel.status == "running" && WorkRunModel.updatedAt <= now - SQL.interval(seconds: staleTimeoutSeconds))
        || (WorkRunModel.status == "failed" && WorkRunModel.updatedAt <= now - SQL.interval(seconds: retrySeconds))
}

/// The SQL of the claim query of `dueWindowFilter`, ordered by attempts and age, limited to one row and locked with
/// `SKIP LOCKED`.
let dynamicIntervalMathSQL =
    #"SELECT "work_runs".* FROM "work_runs" WHERE (("work_runs"."status" = $1 OR ("work_runs"."status" = $2 AND "work_runs"."updated_at" <= ($3 - ($4 * INTERVAL '1 second')))) OR ("work_runs"."status" = $5 AND "work_runs"."updated_at" <= ($6 - (LEAST($7, (POWER($8, LEAST(GREATEST(("work_runs"."attempts" - $9), $10), $11)) * $12)) * INTERVAL '1 second')))) ORDER BY "work_runs"."attempts" ASC, "work_runs"."created_at" ASC LIMIT 1 FOR UPDATE SKIP LOCKED"#
