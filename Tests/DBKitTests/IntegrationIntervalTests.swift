import DBKit
import Foundation
import Testing

@Suite struct IntegrationIntervalTests {
    @Test func intervalHoursEqualityMatchesIntervalColumns() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)

            let exactTwoHours = try await IntervalRowModel.query()
                .filter(SQL.interval(hours: 2) == IntervalRowModel.leaseWindow)
                .all(on: tx)
            #expect(exactTwoHours.map(\.id) == [1])

            let matchesOwnHourColumn = try await IntervalRowModel.query()
                .filter(SQL.interval(hours: IntervalRowModel.baseIntervalHours) == IntervalRowModel.leaseWindow)
                .orderBy(IntervalRowModel.id.asc)
                .all(on: tx)
            #expect(matchesOwnHourColumn.map(\.id) == [1, 2])
        }
    }

    @Test func intervalMinutesWithCoalesceMatchesExpectedRows() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)

            let matched = try await IntervalRowModel.query()
                .filter(SQL.interval(minutes: IntervalRowModel.backoffMinutes ?? 15) == IntervalRowModel.leaseWindow)
                .orderBy(IntervalRowModel.id.asc)
                .all(on: tx)

            #expect(matched.map(\.id) == [3, 4])
        }
    }

    @Test func intervalHelpersCanDriveOrdering() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)

            let ordered = try await IntervalRowModel.query()
                .filter(IntervalRowModel.id.in([1, 2]))
                .orderBy(SQL.interval(hours: IntervalRowModel.baseIntervalHours).asc)
                .all(on: tx)

            #expect(ordered.map(\.id) == [1, 2])
        }
    }

    /// An `Interval` keeps its months, days and microseconds through insert, filter, update and decoding. rust-dbkit's
    /// `build_arguments_accepts_interval` binds the inserted value.
    @Test func intervalRoundtripsThroughInsertFilterAndUpdate() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let halfHourPastADay = Interval(months: 0, days: 1, microseconds: 1_800_000_000)
            let mixed = Interval(months: 1, days: -2, microseconds: 5)

            let inserted = try #require(
                try await IntervalRowModel.insert(IntervalRowModel.Insert(id: 5, baseIntervalHours: 0, leaseWindow: halfHourPastADay))
                    .returningAll().first(on: tx))
            #expect(inserted.leaseWindow == halfHourPastADay)

            let found = try await IntervalRowModel.query().filter(IntervalRowModel.leaseWindow == halfHourPastADay).all(on: tx)
            #expect(found.map(\.id) == [5])

            let updated = try await IntervalRowModel.update()
                .set(IntervalRowModel.leaseWindow, to: mixed)
                .filter(IntervalRowModel.id == 5)
                .returningAll()
                .all(on: tx)
            #expect(updated.map(\.leaseWindow) == [mixed])
            #expect(try await IntervalRowModel.find(5, on: tx)?.leaseWindow == mixed)
        }
    }
    // Waits for slice 14b: `aggregateIntervalsSupportReverseDateArithmetic`, a timestamp plus and minus
    // `SQL.sum(IntervalRowModel.leaseWindow)` of rows 1 and 2 as projections, and the sum of no rows decoding as `nil`.
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        """
        CREATE TEMP TABLE interval_rows (
            id BIGINT PRIMARY KEY, base_interval_hours INTEGER NOT NULL, backoff_minutes INTEGER NULL,
            lease_window INTERVAL NOT NULL
        )
        """)
    try await tx.query(
        """
        INSERT INTO interval_rows (id, base_interval_hours, backoff_minutes, lease_window) VALUES
            (1, 2, NULL, MAKE_INTERVAL(hours => 2)),
            (2, 3, NULL, MAKE_INTERVAL(hours => 3)),
            (3, 99, 30, MAKE_INTERVAL(mins => 30)),
            (4, 99, NULL, MAKE_INTERVAL(mins => 15))
        """)
}
