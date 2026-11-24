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
    // Waits for slice 22: `queryWithDynamicIntervalMathHasExpectedSQLShape`, which also needs `forUpdate().skipLocked()`.
}
