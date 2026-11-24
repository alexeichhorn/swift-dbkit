import DBKit
import Testing

/// Written by hand as in the kit's docs, with keywords as case names.
enum LookupScope: String, DatabaseEnum {
    static let typeName = "lookup_scope"
    case `public`, `internal`
}

@Model(table: "lookup_records")
class LookupRecordModel {
    @Key var id: Int64
    var scope: LookupScope
    var externalKey: String
    var locale: String
    var label: String
}

/// This port binds a value each time it appears, where rust-dbkit binds identical values once and repeats their
/// placeholder. Both mean the same.
@Suite struct RowValueEnumSQLTests {
    /// rust-dbkit renders the second row as `($1::lookup_scope, $4, $5)`.
    @Test func enumRowValueInSQLUsesTypedCastsAndBindReuse() {
        let rendered = LookupRecordModel.query()
            .filter(
                SQL.row(LookupRecordModel.scope, LookupRecordModel.externalKey, LookupRecordModel.locale)
                    .in([(.public, "alpha", "en"), (.public, "beta", "de")])
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "lookup_records".* FROM "lookup_records" WHERE ("lookup_records"."scope", "lookup_records"."external_key", "lookup_records"."locale") IN (($1::lookup_scope, $2, $3), ($4::lookup_scope, $5, $6))"#
        )
        #expect(bindValues(rendered) == ["lookup_scope:public", "alpha", "en", "lookup_scope:public", "beta", "de"])
    }

    @Test func enumRowValueInEmptyCompilesToFalseWithoutBinds() {
        let rendered = LookupRecordModel.query()
            .filter(SQL.row(LookupRecordModel.scope, LookupRecordModel.externalKey, LookupRecordModel.locale).in([]))
            .render()
        #expect(rendered.sql == #"SELECT "lookup_records".* FROM "lookup_records" WHERE FALSE"#)
        #expect(rendered.binds.isEmpty)
    }
}
