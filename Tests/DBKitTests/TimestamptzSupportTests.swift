import DBKit
import Foundation
import Testing

@Suite struct TimestamptzSupportTests {
    @Test func timestamptzRoundtripFiltersAndBetweenWindow() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let startsAt = isoDate("2024-03-14T10:15:00+05:00")
            let endsAt = startsAt + 8 * 3600
            let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

            let inserted = try await seedEventTz(on: tx, id, title: "TZ event", startsAt: startsAt, endsAt: endsAt)
            #expect(inserted.id == id)
            #expect(inserted.startsAt == startsAt)
            #expect(inserted.endsAt == endsAt)

            let found = try #require(
                try await EventTzModel.query()
                    .filter(EventTzModel.id == id)
                    .filter(EventTzModel.startsAt == startsAt)
                    .first(on: tx))
            #expect(found.id == id)
            #expect(found.title == "TZ event")
            #expect(found.startsAt == startsAt)
            #expect(found.endsAt == endsAt)

            let between = try await EventTzModel.query().filter(EventTzModel.startsAt.between(startsAt - 60, startsAt + 60)).all(on: tx)
            #expect(between.map(\.id) == [id])
        }
    }

    @Test func timestamptzNullFilterAndActiveUpdateRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let startsAt = isoDate("2024-01-02T03:04:05Z")
            let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

            let inserted = try await seedEventTz(on: tx, id, title: "Nullable end", startsAt: startsAt, endsAt: nil)
            #expect(inserted.endsAt == nil)
            // Waits for slice 8: `filter(EventTzModel.endsAt == nil)` finds exactly this row.

            let finishedAt = startsAt + 6 * 3600
            let rescheduledStart = startsAt + 2 * 3600
            var active = inserted.active()
            active.startsAt = rescheduledStart
            active.endsAt = finishedAt
            let updated = try await active.update(on: tx)
            #expect(updated.startsAt == rescheduledStart)
            #expect(updated.endsAt == finishedAt)

            var clearing = updated.active()
            clearing.endsAt = nil
            let cleared = try await clearing.update(on: tx)
            #expect(cleared.endsAt == nil)

            let fetched = try #require(try await EventTzModel.find(id, on: tx))
            #expect(fetched.startsAt == rescheduledStart)
            #expect(fetched.endsAt == nil)
        }
    }
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        "CREATE TEMP TABLE events_tz (id UUID PRIMARY KEY, title TEXT NOT NULL, starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NULL)")
}

private func seedEventTz(on tx: Transaction, _ id: UUID, title: String, startsAt: Date, endsAt: Date?) async throws -> EventTzModel {
    try #require(
        try await EventTzModel.insert(EventTzModel.Insert(id: id, title: title, startsAt: startsAt, endsAt: endsAt)).returningAll().first(
            on: tx))
}
