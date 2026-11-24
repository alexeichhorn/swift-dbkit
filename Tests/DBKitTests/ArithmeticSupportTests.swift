import DBKit
import Testing

@Suite struct ArithmeticSupportTests {
    @Test func queryWithNumericArithmeticHasExpectedSQLShape() {
        let rendered = RecordModel.query()
            .filter(RecordModel.leftValue + 1 < RecordModel.baselineValue)
            .filter(RecordModel.rightValue - RecordModel.leftValue > 0)
            .orderBy((RecordModel.baselineValue + RecordModel.leftValue).desc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "records".* FROM "records" WHERE ("records"."left_value" + $1) < "records"."baseline_value" AND ("records"."right_value" - "records"."left_value") > $2 ORDER BY ("records"."baseline_value" + "records"."left_value") DESC"#
        )
        #expect(rendered.binds.map(\.description) == ["1", "0"])
    }

    /// `smallint` with an `integer` operand is `Expr<Int32>`, so it compares with `Int32` values; two `smallint`s stay
    /// `Expr<Int16>`.
    @Test func smallintArithmeticPromotesFiltersToIntegerOperands() {
        let total: Expr<Int32> = CompactRecordModel.leftUnits + CompactRecordModel.rightUnits.cast(to: Int32.self)
        let delta: Expr<Int32> = CompactRecordModel.leftUnits - CompactRecordModel.rightUnits.cast(to: Int32.self)
        let sameWidth: Expr<Int16> = CompactRecordModel.leftUnits + CompactRecordModel.rightUnits
        let rendered = CompactRecordModel.query()
            .filter(total > Int32(9))
            .filter(delta < Int32(4))
            .filter(sameWidth > 1)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "compact_records".* FROM "compact_records" WHERE ("compact_records"."left_units" + CAST("compact_records"."right_units" AS integer)) > $1 AND ("compact_records"."left_units" - CAST("compact_records"."right_units" AS integer)) < $2 AND ("compact_records"."left_units" + "compact_records"."right_units") > $3"#
        )
        #expect(rendered.binds.map(\.description) == ["9", "4", "1"])
    }
}
