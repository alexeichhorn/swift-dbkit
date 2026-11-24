import DBKit
import Testing

@Suite struct DynamicIntervalMathSupportTests {
    /// The annotations fail to compile when a result type changes.
    @Test func dynamicIntervalMathAPIPreservesExpectedExpressionTypes() {
        let _: Expr<Interval> = SQL.interval(seconds: Int64(300))
        // Waits for slice 15: rust-dbkit's `work_runs` model with `attempts: Int32`, `retryExponent`,
        // `SQL.least(SQL.greatest(attempts - 1, 0), 10)` as `Expr<Int32>`, `retrySeconds`, `SQL.power(2.0, retryExponent)
        // * 60.0` as `Expr<Double>`, and `SQL.interval(seconds: retrySeconds)` as `Expr<Interval>`.
    }
    // Waits for slice 22: `queryWithDynamicIntervalMathHasExpectedSQLShape`, which also needs `forUpdate().skipLocked()`.
}
