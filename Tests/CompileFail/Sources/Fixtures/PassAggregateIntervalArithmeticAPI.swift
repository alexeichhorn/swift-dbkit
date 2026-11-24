import DBKit
import Foundation

/// rust-dbkit's `Duration` of `pass_aggregate_interval_arithmetic_api.rs`.
@Model(table: "durations")
class DurationModel {
    @Key var id: Int64
    var elapsed: Interval
    var nullableElapsed: Interval?
}

// `SUM` of intervals is an interval, NULL without input rows, so a timestamp plus or minus it is nullable. `Date`
// stands in for both of rust-dbkit's timestamp types.
private func intervalSumsShiftTimestamps() {
    let utc = Date(timeIntervalSince1970: 1_700_000_000)

    let _: AggregateExpr<Interval?> = SQL.sum(DurationModel.elapsed)
    let _: AggregateExpr<Interval?> = SQL.sum(DurationModel.nullableElapsed)
    let _: Expr<Date?> = utc + SQL.sum(DurationModel.elapsed)
    let _: Expr<Date?> = utc - SQL.sum(DurationModel.elapsed)
}
