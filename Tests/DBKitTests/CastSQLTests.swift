import DBKit
import Foundation
import Testing

/// rust-dbkit's `cast_rows` of `cast_sql.rs`.
@Model(table: "cast_rows")
class CastSourceModel {
    @Key var id: Int64
    var source: String
}

@Suite struct CastSQLTests {
    /// `Date` stands in for rust-dbkit's `timestamp`, `timestamptz` and `date` targets, and Swift has no type for its
    /// `time` target. `Decimal` is a target rust-dbkit doesn't have.
    @Test func compilesEverySupportedCastTargetWithPostgreSQLTypeNames() {
        let source = CastSourceModel.source
        let query: Projection<Bool, Int16, Int32, Int64, Float, Double, Decimal, String, UUID, Date, Interval> = CastSourceModel.query()
            .select(
                source.cast(to: Bool.self).as("as_bool"),
                source.cast(to: Int16.self).as("as_i16"),
                source.cast(to: Int32.self).as("as_i32"),
                source.cast(to: Int64.self).as("as_i64"),
                source.cast(to: Float.self).as("as_f32"),
                source.cast(to: Double.self).as("as_f64"),
                source.cast(to: Decimal.self).as("as_decimal"),
                source.cast(to: String.self).as("as_text"),
                source.cast(to: UUID.self).as("as_uuid"),
                source.cast(to: Date.self).as("as_timestamptz"),
                source.cast(to: Interval.self).as("as_interval")
            )
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT CAST("cast_rows"."source" AS boolean) AS "as_bool", CAST("cast_rows"."source" AS smallint) AS "as_i16", CAST("cast_rows"."source" AS integer) AS "as_i32", CAST("cast_rows"."source" AS bigint) AS "as_i64", CAST("cast_rows"."source" AS real) AS "as_f32", CAST("cast_rows"."source" AS double precision) AS "as_f64", CAST("cast_rows"."source" AS numeric) AS "as_decimal", CAST("cast_rows"."source" AS text) AS "as_text", CAST("cast_rows"."source" AS uuid) AS "as_uuid", CAST("cast_rows"."source" AS timestamptz) AS "as_timestamptz", CAST("cast_rows"."source" AS interval) AS "as_interval" FROM "cast_rows""#
        )
        #expect(rendered.binds.isEmpty)
    }
}
