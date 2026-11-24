import DBKit

/// rust-dbkit's `schedules` of `pass_interval_api.rs`.
@Model(table: "schedules")
class ScheduleModel {
    @Key var id: Int64
    var baseIntervalHours: Int32
    var backoffMinutes: Int32?
}

private func intervalExpressionsOrderQueries() {
    let base: Expr<Interval> = SQL.interval(hours: 6)
    let jitter: Expr<Interval> = SQL.interval(seconds: 0.5)
    let retryHours: Expr<Interval> = SQL.interval(hours: ScheduleModel.baseIntervalHours)
    let retryMinutes: Expr<Interval> = SQL.interval(minutes: ScheduleModel.backoffMinutes ?? 15)

    _ = ScheduleModel.query().orderBy(retryHours.asc).orderBy(retryMinutes.asc).render()

    let projection: Projection<Interval, Interval, Interval, Interval> = ScheduleModel.query()
        .select(base.as("base_interval"), jitter.as("jitter"), retryHours.as("retry_hours"), retryMinutes.as("retry_minutes"))
        .orderBy(retryHours.asc)
        .orderBy(retryMinutes.asc)
    _ = projection.render()
}
