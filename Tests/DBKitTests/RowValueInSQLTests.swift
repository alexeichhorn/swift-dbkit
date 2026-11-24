import DBKit
import Foundation
import Testing

/// rust-dbkit's `lookup_entries` of `row_value_in_sql.rs`, with a key `@Model` requires.
@Model(table: "lookup_entries")
class LookupEntryModel {
    @Key var id: Int64
    var namespace: String
    var name: String
    var locale: String
}

/// This port binds a value each time it appears, where rust-dbkit binds identical values once and repeats their
/// placeholder. Both mean the same.
@Suite struct RowValueInSQLTests {
    @Test func compilesRowValueInExpressionForThreeColumns() {
        let rendered = LookupEntryModel.query()
            .filter(
                SQL.row(LookupEntryModel.namespace, LookupEntryModel.name, LookupEntryModel.locale)
                    .in([("cities", "berlin", "en"), ("countries", "germany", "de")])
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "lookup_entries".* FROM "lookup_entries" WHERE ("lookup_entries"."namespace", "lookup_entries"."name", "lookup_entries"."locale") IN (($1, $2, $3), ($4, $5, $6))"#
        )
        #expect(rendered.binds.map(\.description) == ["cities", "berlin", "en", "countries", "germany", "de"])
    }

    @Test func rowValueInEmptyCompilesToFalseWithoutBinds() {
        let rendered = LookupEntryModel.query()
            .filter(SQL.row(LookupEntryModel.namespace, LookupEntryModel.name, LookupEntryModel.locale).in([]))
            .render()
        #expect(rendered.sql == #"SELECT "lookup_entries".* FROM "lookup_entries" WHERE FALSE"#)
        #expect(rendered.binds.isEmpty)
    }

    /// rust-dbkit renders the second row as `($1, $4, $5)`.
    @Test func rowValueInReusesIdenticalBindsAcrossRows() {
        let rendered = LookupEntryModel.query()
            .filter(
                SQL.row(LookupEntryModel.namespace, LookupEntryModel.name, LookupEntryModel.locale)
                    .in([("cities", "berlin", "en"), ("cities", "munich", "de")])
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "lookup_entries".* FROM "lookup_entries" WHERE ("lookup_entries"."namespace", "lookup_entries"."name", "lookup_entries"."locale") IN (($1, $2, $3), ($4, $5, $6))"#
        )
        #expect(rendered.binds.map(\.description) == ["cities", "berlin", "en", "cities", "munich", "de"])
    }

    /// Each value binds with its column's type: `bigint`, `integer` and a timestamp.
    @Test func rowValueInSupportsMixedIntegerAndTimestampTypes() throws {
        let first = isoDate("2024-01-02T03:04:05Z")
        let second = isoDate("2024-01-03T06:07:08Z")

        let rendered = RevisionSnapshotModel.query()
            .filter(
                SQL.row(RevisionSnapshotModel.seriesID, RevisionSnapshotModel.revision, RevisionSnapshotModel.capturedAt)
                    .in([(11, 1, first), (11, 2, second)])
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "revision_snapshots".* FROM "revision_snapshots" WHERE ("revision_snapshots"."series_id", "revision_snapshots"."revision", "revision_snapshots"."captured_at") IN (($1, $2, $3), ($4, $5, $6))"#
        )
        try #require(rendered.binds.count == 6)
        #expect(rendered.binds[0].value as? Int64 == 11)
        #expect(rendered.binds[1].value as? Int32 == 1)
        #expect(rendered.binds[2].value as? Date == first)
        #expect(rendered.binds[3].value as? Int64 == 11)
        #expect(rendered.binds[4].value as? Int32 == 2)
        #expect(rendered.binds[5].value as? Date == second)
    }
}
