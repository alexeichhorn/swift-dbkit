import DBKit
import Foundation

@Model(table: "events_tz")
class EventTzModel {
    @Key var id: UUID
    var title: String
    var startsAt: Date
    var endsAt: Date?
}

private func useUTCDates() {
    let nilUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    // 2024-01-02 03:04:05 UTC.
    let startsAt = Date(timeIntervalSince1970: 1_704_164_645)
    let endsAt = startsAt + 3600

    _ = EventTzModel.query()
        .filter(EventTzModel.startsAt == startsAt)
        .filter(EventTzModel.startsAt.between(startsAt, endsAt))
    // Waits for slice 8: `.filter(EventTzModel.endsAt == nil)` on that query.

    _ = EventTzModel.insert(EventTzModel.Insert(id: nilUUID, title: "TZ", startsAt: startsAt, endsAt: endsAt))

    _ = EventTzModel.update()
        .set(EventTzModel.startsAt, to: endsAt)
        .set(EventTzModel.endsAt, to: endsAt)

    var active = ActiveModel<EventTzModel>()
    active.id = nilUUID
    active.title = "Active TZ"
    active.startsAt = startsAt
    active.endsAt = nil
    _ = active
}
