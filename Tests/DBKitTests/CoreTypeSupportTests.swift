import DBKit
import Foundation
import Testing

/// rust-dbkit's `events_tz` table of `select_supports_utc_datetime_between_and_null_filters`, with a nullable
/// `starts_at`.
@Model(table: "events_tz")
class NullableStartEventModel {
    @Key var id: UUID
    var startsAt: Date?
}

private let nilUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

@Suite struct CoreTypeSupportTests {
    /// `Date` stands in for both `NaiveDateTime` and `NaiveDate`; Swift has no type for rust-dbkit's `NaiveTime`.
    @Test func selectBindsUUIDDatetimeDateTime() throws {
        let day = isoDate("2024-01-02T00:00:00Z")
        let datetime = isoDate("2024-01-02T03:04:05Z")

        let rendered = EventModel.query()
            .filter(EventModel.id == nilUUID)
            .filter(EventModel.startsAt == datetime)
            .filter(EventModel.day == day)
            .render()

        try #require(rendered.binds.count == 3)
        #expect(rendered.binds[0].value as? UUID == nilUUID)
        #expect(rendered.binds[1].value as? Date == datetime)
        #expect(rendered.binds[2].value as? Date == day)
    }

    @Test func selectBindsUTCDatetime() throws {
        let datetime = isoDate("2024-01-02T03:04:05Z")

        let rendered = EventTzModel.query().filter(EventTzModel.startsAt == datetime).render()

        try #require(rendered.binds.count == 1)
        #expect(rendered.binds[0].value as? Date == datetime)
    }

    @Test func selectSupportsUTCDatetimeBetweenAndNullFilters() throws {
        let low = isoDate("2024-01-02T03:00:00Z")
        let high = low + 30 * 60

        let rendered = NullableStartEventModel.query()
            .filter(NullableStartEventModel.startsAt == nil)
            .filter(NullableStartEventModel.startsAt.between(low, high))
            .render()

        #expect(rendered.sql.contains("IS NULL"))
        #expect(rendered.sql.contains(#""events_tz"."starts_at" BETWEEN $1 AND $2"#))
        try #require(rendered.binds.count == 2)
        #expect(rendered.binds[0].value as? Date == low)
        #expect(rendered.binds[1].value as? Date == high)
    }

    @Test func selectBindsJSON() throws {
        let payload = JSONPayload(name: "alice", active: true)

        let rendered = JSONRowModel.query().filter(JSONRowModel.data == payload).render()

        try #require(rendered.binds.count == 1)
        #expect(rendered.binds[0].value as? JSONPayload == payload)
    }

    @Test func selectBindsStringArray() throws {
        let items = ["a", "b"]

        let rendered = ProfileModel.query().filter(ProfileModel.tags == items).render()

        try #require(rendered.binds.count == 1)
        #expect(rendered.binds[0].value as? [String] == items)
    }

    @Test func selectBindsBytes() throws {
        let payload = Data([0, 1, 2, 255])

        let rendered = BlobRowModel.query().filter(BlobRowModel.data == payload).render()

        try #require(rendered.binds.count == 1)
        #expect(rendered.binds[0].value as? Data == payload)
    }

    /// rust-dbkit's `Value::from`; a bind keeps all three components.
    @Test func valueFromInterval() {
        let interval = Interval(months: 0, days: 2, microseconds: 3_600_000_000)

        let bind = Bind(interval)

        #expect(bind.value as? Interval == interval)
        #expect(bind.description == "0 mons 2 days 3600000000 us")
    }

    @Test func selectBindsInterval() throws {
        let interval = Interval(months: 0, days: 0, microseconds: 7_200_000_000)

        let rendered = IntervalRowModel.query().filter(IntervalRowModel.leaseWindow == interval).render()

        try #require(rendered.binds.count == 1)
        #expect(rendered.binds[0].value as? Interval == interval)
    }
}
