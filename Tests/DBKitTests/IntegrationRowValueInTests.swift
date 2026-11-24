import DBKit
import Foundation
import Testing

/// rust-dbkit's `lookup_rows` of `integration_row_value_in.rs`. Text stands in for its `scope` column of the enum
/// `lookup_scope`, with the enum's labels; the `tasks` part of `IntegrationTests.postgresTypesAggregatesAndFunctions`
/// runs a row value over an enum column.
@Model(table: "lookup_rows")
class LookupRowModel {
    @Key @AutoIncrement var id: Int64
    var scope: String
    var externalKey: String
    var locale: String
    var label: String
}

@Suite struct IntegrationRowValueInTests {
    @Test func rowValueInReturnsRowsMatchingRequestedCompositeKeys() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let alphaEn = try await seedRow(on: tx, "public", "alpha", "en", "Alpha")
            _ = try await seedRow(on: tx, "public", "alpha", "de", "Alpha DE")
            let betaEn = try await seedRow(on: tx, "internal", "beta", "en", "Beta")
            _ = try await seedRow(on: tx, "internal", "gamma", "en", "Gamma")

            let rows = try await LookupRowModel.query()
                .filter(
                    SQL.row(LookupRowModel.scope, LookupRowModel.externalKey, LookupRowModel.locale)
                        .in([("public", "alpha", "en"), ("internal", "beta", "en")])
                )
                .orderBy(LookupRowModel.id.asc)
                .all(on: tx)

            #expect(rows.map(\.id) == [alphaEn.id, betaEn.id])
            #expect(rows.map(\.label) == ["Alpha", "Beta"])
        }
    }

    @Test func rowValueInEmptyInputReturnsNoRows() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedRow(on: tx, "public", "alpha", "en", "Alpha")
            _ = try await seedRow(on: tx, "internal", "beta", "en", "Beta")

            let rows = try await LookupRowModel.query()
                .filter(SQL.row(LookupRowModel.scope, LookupRowModel.externalKey, LookupRowModel.locale).in([]))
                .all(on: tx)

            #expect(rows.isEmpty)
        }
    }

    @Test func rowValueInDuplicateRequestedKeysDoNotDuplicateRows() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let alphaEn = try await seedRow(on: tx, "public", "alpha", "en", "Alpha")
            let betaEn = try await seedRow(on: tx, "internal", "beta", "en", "Beta")

            let rows = try await LookupRowModel.query()
                .filter(
                    SQL.row(LookupRowModel.scope, LookupRowModel.externalKey, LookupRowModel.locale)
                        .in([("public", "alpha", "en"), ("public", "alpha", "en"), ("internal", "beta", "en")])
                )
                .orderBy(LookupRowModel.id.asc)
                .all(on: tx)

            #expect(rows.map(\.id) == [alphaEn.id, betaEn.id])
        }
    }

    @Test func rowValueInComposesWithAdditionalFilters() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let alphaEn = try await seedRow(on: tx, "public", "alpha", "en", "Alpha")
            _ = try await seedRow(on: tx, "internal", "beta", "en", "Beta")

            let rows = try await LookupRowModel.query()
                .filter(LookupRowModel.scope == "public")
                .filter(
                    SQL.row(LookupRowModel.scope, LookupRowModel.externalKey, LookupRowModel.locale)
                        .in([("public", "alpha", "en"), ("internal", "beta", "en")])
                )
                .orderBy(LookupRowModel.id.asc)
                .all(on: tx)

            #expect(rows.count == 1)
            #expect(rows.first?.id == alphaEn.id)
            #expect(rows.first?.label == "Alpha")
        }
    }

    @Test func rowValueInSupportsIntegerAndTimestampColumns() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let first = isoDate("2024-04-01T09:00:00Z")
            let second = isoDate("2024-04-01T10:00:00Z")
            let third = isoDate("2024-04-02T09:00:00Z")

            let firstRow = try await seedRevisionSnapshot(on: tx, 42, 1, first, "First")
            let secondRow = try await seedRevisionSnapshot(on: tx, 42, 2, second, "Second")
            _ = try await seedRevisionSnapshot(on: tx, 7, 1, first, "Other series")
            _ = try await seedRevisionSnapshot(on: tx, 42, 3, third, "Other time")

            let rows = try await RevisionSnapshotModel.query()
                .filter(
                    SQL.row(RevisionSnapshotModel.seriesID, RevisionSnapshotModel.revision, RevisionSnapshotModel.capturedAt)
                        .in([(42, 1, first), (42, 2, second)])
                )
                .orderBy(RevisionSnapshotModel.id.asc)
                .all(on: tx)

            #expect(rows.map(\.id) == [firstRow.id, secondRow.id])
            #expect(rows.map(\.note) == ["First", "Second"])
        }
    }
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        """
        CREATE TEMP TABLE lookup_rows (
            id BIGSERIAL PRIMARY KEY, scope TEXT NOT NULL, external_key TEXT NOT NULL, locale TEXT NOT NULL, label TEXT NOT NULL,
            UNIQUE (scope, external_key, locale)
        )
        """)
    try await tx.query(
        """
        CREATE TEMP TABLE revision_snapshots (
            id BIGSERIAL PRIMARY KEY, series_id BIGINT NOT NULL, revision INTEGER NOT NULL, captured_at TIMESTAMPTZ NOT NULL,
            note TEXT NOT NULL, UNIQUE (series_id, revision, captured_at)
        )
        """)
}

private func seedRow(
    on tx: Transaction, _ scope: String, _ externalKey: String, _ locale: String, _ label: String
) async throws -> LookupRowModel {
    try #require(
        try await LookupRowModel.insert(LookupRowModel.Insert(scope: scope, externalKey: externalKey, locale: locale, label: label))
            .returningAll().first(on: tx))
}

private func seedRevisionSnapshot(
    on tx: Transaction, _ seriesID: Int64, _ revision: Int32, _ capturedAt: Date, _ note: String
) async throws -> RevisionSnapshotModel {
    try #require(
        try await RevisionSnapshotModel.insert(
            RevisionSnapshotModel.Insert(seriesID: seriesID, revision: revision, capturedAt: capturedAt, note: note)
        )
        .returningAll().first(on: tx))
}
