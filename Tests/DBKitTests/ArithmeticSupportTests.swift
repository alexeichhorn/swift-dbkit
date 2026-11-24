import DBKit
import Foundation
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

    @Test func queryWithTimestampOffsetArithmeticHasExpectedSQLShape() throws {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let rendered = RecordModel.query()
            .filter(RecordModel.occurredAt + SQL.interval(hours: RecordModel.leftValue) <= cutoff)
            .orderBy((RecordModel.occurredAt - SQL.interval(hours: 1)).asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "records".* FROM "records" WHERE ("records"."occurred_at" + ("records"."left_value" * INTERVAL '1 hour')) <= $1 ORDER BY ("records"."occurred_at" - ($2 * INTERVAL '1 hour')) ASC"#
        )
        try #require(rendered.binds.count == 2)
        #expect(rendered.binds[0].value as? Date == cutoff)
        #expect(rendered.binds[1].value as? Int == 1)
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

    /// rust-dbkit orders by the alias `computed_value`, which this port doesn't support yet, so it orders by the
    /// expression.
    @Test func selectOnlyAcceptsArithmeticProjectionAliases() {
        let computedValue: Expr<Int32> = RecordModel.baselineValue + RecordModel.leftValue
        let rendered = RecordModel.query().select(computedValue.as("computed_value")).orderBy(computedValue.desc).render()
        #expect(
            rendered.sql
                == #"SELECT ("records"."baseline_value" + "records"."left_value") AS "computed_value" FROM "records" ORDER BY ("records"."baseline_value" + "records"."left_value") DESC"#
        )
        #expect(rendered.binds.isEmpty)
    }

    /// As in `smallintArithmeticPromotesFiltersToIntegerOperands`, an `integer` operand makes the projection
    /// `Expr<Int32>`; two `smallint`s stay `Expr<Int16>`.
    @Test func smallintArithmeticProjectionIsUsableAsIntegerExpression() {
        let totalUnits: Expr<Int32> = CompactRecordModel.leftUnits + CompactRecordModel.rightUnits.cast(to: Int32.self)
        let delta: Expr<Int16> = CompactRecordModel.leftUnits - CompactRecordModel.rightUnits
        let query: Projection<Int32> = CompactRecordModel.query().select(totalUnits.as("total_units")).orderBy(delta.desc)
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT ("compact_records"."left_units" + CAST("compact_records"."right_units" AS integer)) AS "total_units" FROM "compact_records" ORDER BY ("compact_records"."left_units" - "compact_records"."right_units") DESC"#
        )
        #expect(rendered.binds.isEmpty)
    }
}
