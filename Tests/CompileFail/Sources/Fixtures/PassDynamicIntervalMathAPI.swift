import DBKit
import Foundation

/// rust-dbkit's `WorkRun` of `pass_dynamic_interval_math_api.rs`. `Date` stands in for its `timestamp` columns.
@Model(table: "work_runs")
class WorkRunModel {
    @Key var id: Int64
    var status: String
    var attempts: Int32
    var updatedAt: Date
    var createdAt: Date
}

private func dynamicIntervalMath() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    let retryExponent: Expr<Int32> = SQL.least(SQL.greatest(WorkRunModel.attempts - 1, 0), 10)
    let retrySeconds: Expr<Double> = SQL.least(3_600.0, SQL.power(2.0, retryExponent) * 60.0)
    let _: Expr<Interval> = SQL.interval(seconds: Int64(300))
    let _: Expr<Interval> = SQL.interval(seconds: retrySeconds)

    _ = WorkRunModel.query()
        .filter(
            WorkRunModel.status == "pending"
                || (WorkRunModel.status == "running" && WorkRunModel.updatedAt <= now - SQL.interval(seconds: Int64(300)))
                || (WorkRunModel.status == "failed" && WorkRunModel.updatedAt <= now - SQL.interval(seconds: retrySeconds))
        )
        .orderBy(WorkRunModel.attempts.asc)
        .orderBy(WorkRunModel.createdAt.asc)
        .forUpdate(.skipLocked)
        .limit(1)
        .render()
}
