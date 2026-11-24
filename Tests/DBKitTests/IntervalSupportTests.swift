import DBKit
import Foundation
import Testing

/// rust-dbkit's `schedules` of `interval_support.rs`.
@Model(table: "schedules")
class ScheduleModel {
    @Key var id: Int64
    var baseIntervalHours: Int32
    var backoffMinutes: Int32
    var optionalIntervalUnits: Int32?
    var optionalSeconds: Double?
    var retryInterval: Interval
}

/// rust-dbkit selects most interval expressions as projections. Until projections exist, the expressions are ordered by,
/// which renders them and their binds in the same order.
@Suite struct IntervalSupportTests {
    @Test func compilesIntervalHoursWithLiteral() {
        let rendered = ScheduleModel.query().orderBy(SQL.interval(hours: 6).asc).render()
        #expect(rendered.sql == #"SELECT "schedules".* FROM "schedules" ORDER BY ($1 * INTERVAL '1 hour') ASC"#)
        #expect(typedBinds(rendered) == ["Int(6)"])
        // Waits for slice 14: the expression as the projection `lease_window`.
    }

    @Test func compilesIntervalHoursWithColumn() {
        let rendered = ScheduleModel.query().orderBy(SQL.interval(hours: ScheduleModel.baseIntervalHours).asc).render()
        #expect(
            rendered.sql
                == #"SELECT "schedules".* FROM "schedules" ORDER BY ("schedules"."base_interval_hours" * INTERVAL '1 hour') ASC"#)
        #expect(rendered.binds.isEmpty)
        // Waits for slice 14: the expression as the projection `lease_window`.
    }

    /// rust-dbkit coalesces the required `base_interval_hours`; `??` takes a nullable column, so the nested expression
    /// coalesces `optional_interval_units` here.
    @Test func compilesIntervalHoursWithNestedExpressionPart() {
        let rendered = ScheduleModel.query().orderBy(SQL.interval(hours: ScheduleModel.optionalIntervalUnits ?? 24).asc).render()
        #expect(
            rendered.sql
                == #"SELECT "schedules".* FROM "schedules" ORDER BY (COALESCE("schedules"."optional_interval_units", $1) * INTERVAL '1 hour') ASC"#
        )
        #expect(typedBinds(rendered) == ["Int32(24)"])
        // Waits for slice 14: the expression as the projection `lease_window`.
    }

    @Test func compilesIntervalMinutesWithNegativeLiteral() {
        let rendered = ScheduleModel.query().orderBy(SQL.interval(minutes: -30).asc).render()
        #expect(rendered.sql == #"SELECT "schedules".* FROM "schedules" ORDER BY ($1 * INTERVAL '1 minute') ASC"#)
        #expect(typedBinds(rendered) == ["Int(-30)"])
        // Waits for slice 14: the expression as the projection `retry_after`.
    }

    @Test func compilesIntervalDaysWithLiteral() {
        let rendered = ScheduleModel.query().orderBy(SQL.interval(days: 2).asc).render()
        #expect(rendered.sql == #"SELECT "schedules".* FROM "schedules" ORDER BY ($1 * INTERVAL '1 day') ASC"#)
        #expect(typedBinds(rendered) == ["Int(2)"])
        // Waits for slice 14: the expression as the projection `cooldown`.
    }

    @Test func compilesIntervalSecondsWithFractionalLiteral() {
        let rendered = ScheduleModel.query().orderBy(SQL.interval(seconds: 1.5).asc).render()
        #expect(rendered.sql == #"SELECT "schedules".* FROM "schedules" ORDER BY ($1 * INTERVAL '1 second') ASC"#)
        #expect(typedBinds(rendered) == ["Double(1.5)"])
        // Waits for slice 14: the expression as the projection `jitter`.
    }

    @Test func compilesIntervalConstructorsWithNullableColumns() {
        let days: Expr<Interval?> = SQL.interval(days: ScheduleModel.optionalIntervalUnits)
        let hours: Expr<Interval?> = SQL.interval(hours: ScheduleModel.optionalIntervalUnits)
        let minutes: Expr<Interval?> = SQL.interval(minutes: ScheduleModel.optionalIntervalUnits)
        let seconds: Expr<Interval?> = SQL.interval(seconds: ScheduleModel.optionalSeconds)

        let rendered = ScheduleModel.query().orderBy(days.asc, hours.asc, minutes.asc, seconds.asc).render()

        #expect(
            rendered.sql
                == #"SELECT "schedules".* FROM "schedules" ORDER BY ("schedules"."optional_interval_units" * INTERVAL '1 day') ASC, ("schedules"."optional_interval_units" * INTERVAL '1 hour') ASC, ("schedules"."optional_interval_units" * INTERVAL '1 minute') ASC, ("schedules"."optional_seconds" * INTERVAL '1 second') ASC"#
        )
        #expect(rendered.binds.isEmpty)
        // Waits for slice 14: the four expressions as the projections `days`, `hours`, `minutes` and `seconds`.
    }

    /// `Date` stands in for both of rust-dbkit's timestamp types, so its four expressions are two here.
    @Test func compilesTimestampLiteralsWithNullableIntervalExpressions() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let added: Expr<Date?> = timestamp + SQL.interval(hours: ScheduleModel.optionalIntervalUnits)
        let subtracted: Expr<Date?> = timestamp - SQL.interval(hours: ScheduleModel.optionalIntervalUnits)

        let rendered = ScheduleModel.query().orderBy(added.asc, subtracted.asc).render()

        #expect(
            rendered.sql
                == #"SELECT "schedules".* FROM "schedules" ORDER BY ($1 + ("schedules"."optional_interval_units" * INTERVAL '1 hour')) ASC, ($2 - ("schedules"."optional_interval_units" * INTERVAL '1 hour')) ASC"#
        )
        try #require(rendered.binds.count == 2)
        #expect(rendered.binds[0].value as? Date == timestamp)
        #expect(rendered.binds[1].value as? Date == timestamp)
        // Waits for slice 14: the two expressions as the projections `added` and `subtracted`.
    }

    @Test func intervalExpressionCanCompareToIntervalColumns() {
        let rendered = ScheduleModel.query().filter(SQL.interval(hours: 1) == ScheduleModel.retryInterval).render()
        #expect(
            rendered.sql
                == #"SELECT "schedules".* FROM "schedules" WHERE ($1 * INTERVAL '1 hour') = "schedules"."retry_interval""#)
        #expect(typedBinds(rendered) == ["Int(1)"])
    }

    @Test func intervalExpressionCanBeUsedInOrderBy() {
        let rendered = ScheduleModel.query().orderBy(SQL.interval(minutes: ScheduleModel.backoffMinutes).asc).limit(10).render()
        #expect(
            rendered.sql
                == #"SELECT "schedules".* FROM "schedules" ORDER BY ("schedules"."backoff_minutes" * INTERVAL '1 minute') ASC LIMIT 10"#
        )
        #expect(rendered.binds.isEmpty)
    }
}

/// Each bind as `<type>(<value>)`, since the type of a bound interval amount is part of what PostgreSQL computes with.
private func typedBinds(_ rendered: RenderedSQL) -> [String] {
    rendered.binds.map { "\(type(of: $0.value))(\($0))" }
}
