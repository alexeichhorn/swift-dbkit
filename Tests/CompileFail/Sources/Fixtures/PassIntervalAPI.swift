import DBKit

/// rust-dbkit's `schedules` of `pass_interval_api.rs`.
@Model(table: "schedules")
class ScheduleModel {
    @Key var id: Int64
    var baseIntervalHours: Int32
    var backoffMinutes: Int32?
}

private func intervalExpressionsOrderQueries() {
    let _: Expr<Interval> = SQL.interval(hours: 6)
    let _: Expr<Interval> = SQL.interval(seconds: 0.5)
    let retryHours: Expr<Interval> = SQL.interval(hours: ScheduleModel.baseIntervalHours)
    let retryMinutes: Expr<Interval> = SQL.interval(minutes: ScheduleModel.backoffMinutes ?? 15)

    _ = ScheduleModel.query().orderBy(retryHours.asc).orderBy(retryMinutes.asc).render()
    // Waits for slice 14: `SQL.interval(hours: 6)`, `SQL.interval(seconds: 0.5)`, `retryHours` and `retryMinutes` as
    // the projections `base_interval`, `jitter`, `retry_hours` and `retry_minutes`.
}
