import DBKit
import Foundation
import Testing

/// The `users` table of rust-dbkit's `sql_compiler.rs`, with nullable `email` and `score`.
@Model(table: "users")
class CompilerUserModel {
    @Key var id: Int64
    var email: String?
    var backupEmail: String?
    var score: Int64?
}

/// The `compact_rows` table of rust-dbkit's `sql_compiler.rs`: two `smallint` columns.
@Model(table: "compact_rows")
class CompilerCompactRowModel {
    @Key var id: Int64
    var leftUnits: Int16
    var rightUnits: Int16
}

/// The `text_samples` table of rust-dbkit's `sql_compiler.rs`, with nullable `body` and `optional_width`.
@Model(table: "text_samples")
class CompilerTextSampleModel {
    @Key var id: Int64
    var body: String?
    var title: String
    var width: Int32
    var optionalWidth: Int32?
}

private typealias TS = CompilerTextSampleModel

/// The `window_rows` table of rust-dbkit's `sql_compiler.rs`. `Date` stands in for its `timestamp` column.
@Model(table: "window_rows")
class CompilerWindowRowModel {
    @Key var id: Int64
    var anchorAt: Date
    var offsetUnits: Int32
}

@Suite struct SQLCompilerTests {
    @Test func compilesBasicFilter() {
        let rendered = CompilerUserModel.query().filter(CompilerUserModel.email == "a@b.com").render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" = $1"#)
        #expect(rendered.binds.map(\.description) == ["a@b.com"])
    }

    @Test func compilesBoolComposition() {
        let rendered = CompilerUserModel.query()
            .filter(CompilerUserModel.id > 10 && CompilerUserModel.email.ilike("%test%"))
            .render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE ("users"."id" > $1 AND "users"."email" ILIKE $2)"#)
        #expect(rendered.binds.map(\.description) == ["10", "%test%"])
    }

    @Test func compilesInExpression() {
        let rendered = CompilerUserModel.query().filter(CompilerUserModel.id.in([1, 2, 3])).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."id" IN ($1, $2, $3)"#)
        #expect(rendered.binds.map(\.description) == ["1", "2", "3"])
    }

    @Test func compilesIsNullExpression() {
        let predicate: Expr<Bool> = CompilerUserModel.email.isNull
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" IS NULL"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesEqNoneAsIsNull() {
        let predicate: Expr<Bool?> = CompilerUserModel.email == nil
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" IS NULL"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesEqSomeOnNullableColumnAsBoundValue() {
        let email: String? = "a@b.com"
        let predicate: Expr<Bool?> = CompilerUserModel.email == email
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" = $1"#)
        #expect(rendered.binds.map(\.description) == ["a@b.com"])
    }

    @Test func compilesNeNoneAsIsNotNull() {
        let predicate: Expr<Bool?> = CompilerUserModel.email != nil
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" IS NOT NULL"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesNullableOrderedComparisonsWithOptionalValues() {
        let five: Int64? = 5
        let some: Expr<Bool?> = CompilerUserModel.score < five
        let someRendered = CompilerUserModel.query().filter(some).render()
        #expect(someRendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."score" < $1"#)
        #expect(someRendered.binds.map(\.description) == ["5"])

        let missing: Int64? = nil
        let none: Expr<Bool?> = CompilerUserModel.score >= missing
        let noneRendered = CompilerUserModel.query().filter(none).render()
        #expect(noneRendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."score" >= NULL"#)
        #expect(noneRendered.binds.isEmpty)
    }

    @Test func compilesCoalesceFunctionFilter() {
        let predicate: Expr<Bool> = (CompilerUserModel.email ?? "unknown") == "ALPHA"
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE COALESCE("users"."email", $1) = $2"#)
        #expect(rendered.binds.map(\.description) == ["unknown", "ALPHA"])
    }

    @Test func compilesCoalesceTwoColumns() {
        let predicate: Expr<Bool?> = (CompilerUserModel.email ?? CompilerUserModel.backupEmail) == "alpha@db.com"
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE COALESCE("users"."email", "users"."backup_email") = $1"#)
        #expect(rendered.binds.map(\.description) == ["alpha@db.com"])
    }

    @Test func compilesSelectQuery() {
        let rendered = CompilerUserModel.query()
            .filter(CompilerUserModel.email.like("%example%"))
            .limit(5)
            .offset(10)
            .render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" LIKE $1 LIMIT 5 OFFSET 10"#)
        #expect(rendered.binds.map(\.description) == ["%example%"])
    }

    @Test func compilesBetweenExpression() {
        let rendered = CompilerUserModel.query().filter(CompilerUserModel.id.between(1, 5)).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."id" BETWEEN $1 AND $2"#)
        #expect(rendered.binds.map(\.description) == ["1", "5"])
    }

    @Test func compilesAddOperatorFilter() {
        let predicate: Expr<Bool> = SaleModel.amount + 5 > 10
        let rendered = SaleModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "sales".* FROM "sales" WHERE ("sales"."amount" + $1) > $2"#)
        #expect(rendered.binds.map(\.description) == ["5", "10"])
    }

    @Test func compilesSubOperatorFilter() {
        let predicate: Expr<Bool> = SaleModel.amount - 7 <= 100
        let rendered = SaleModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "sales".* FROM "sales" WHERE ("sales"."amount" - $1) <= $2"#)
        #expect(rendered.binds.map(\.description) == ["7", "100"])
    }

    @Test func compilesNestedArithmeticExpressionWithStableParentheses() {
        let predicate: Expr<Bool> = ((SaleModel.amount + 5) - SaleModel.id) + 2 >= 20
        let rendered = SaleModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "sales".* FROM "sales" WHERE ((("sales"."amount" + $1) - "sales"."id") + $2) >= $3"#)
        #expect(rendered.binds.map(\.description) == ["5", "2", "20"])
    }

    @Test func compilesTimestampPlusCustomOffsetFunctionFilter() throws {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let predicate: Expr<Bool> = CompilerWindowRowModel.anchorAt + SQL.interval(hours: CompilerWindowRowModel.offsetUnits) <= cutoff
        let rendered = CompilerWindowRowModel.query().filter(predicate).render()
        #expect(
            rendered.sql
                == #"SELECT "window_rows".* FROM "window_rows" WHERE ("window_rows"."anchor_at" + ("window_rows"."offset_units" * INTERVAL '1 hour')) <= $1"#
        )
        try #require(rendered.binds.count == 1)
        #expect(rendered.binds[0].value as? Date == cutoff)
    }

    /// `smallint` with an `integer` operand is `Expr<Int32>`, so it compares with an `Int32` value. Two `smallint`s, or a
    /// `smallint` and an untyped literal, stay `Expr<Int16>`, as in PostgreSQL.
    @Test func compilesSmallintAddFilterAgainstIntegerRHS() {
        let total: Expr<Int32> = CompilerCompactRowModel.leftUnits + CompilerCompactRowModel.rightUnits.cast(to: Int32.self)
        let rendered = CompilerCompactRowModel.query().filter(total > Int32(10)).render()
        #expect(
            rendered.sql
                == #"SELECT "compact_rows".* FROM "compact_rows" WHERE ("compact_rows"."left_units" + CAST("compact_rows"."right_units" AS integer)) > $1"#
        )
        #expect(rendered.binds.map(\.description) == ["10"])

        let sameWidth: Expr<Int16> = CompilerCompactRowModel.leftUnits + CompilerCompactRowModel.rightUnits
        let literal: Expr<Int16> = CompilerCompactRowModel.leftUnits + 1
        let sameWidthRendered = CompilerCompactRowModel.query().filter(sameWidth > literal).render()
        #expect(
            sameWidthRendered.sql
                == #"SELECT "compact_rows".* FROM "compact_rows" WHERE ("compact_rows"."left_units" + "compact_rows"."right_units") > ("compact_rows"."left_units" + $1)"#
        )
        #expect(sameWidthRendered.binds.map(\.description) == ["1"])
    }

    @Test func compilesSmallintSubFilterAgainstIntegerRHS() {
        let delta: Expr<Int32> = CompilerCompactRowModel.leftUnits - CompilerCompactRowModel.rightUnits.cast(to: Int32.self)
        let rendered = CompilerCompactRowModel.query().filter(delta <= Int32(3)).render()
        #expect(
            rendered.sql
                == #"SELECT "compact_rows".* FROM "compact_rows" WHERE ("compact_rows"."left_units" - CAST("compact_rows"."right_units" AS integer)) <= $1"#
        )
        #expect(rendered.binds.map(\.description) == ["3"])

        let sameWidth: Expr<Int16> = CompilerCompactRowModel.leftUnits - CompilerCompactRowModel.rightUnits
        let literal: Expr<Int16> = 3 - CompilerCompactRowModel.rightUnits
        let sameWidthRendered = CompilerCompactRowModel.query().filter(sameWidth <= literal).render()
        #expect(
            sameWidthRendered.sql
                == #"SELECT "compact_rows".* FROM "compact_rows" WHERE ("compact_rows"."left_units" - "compact_rows"."right_units") <= ($1 - "compact_rows"."right_units")"#
        )
        #expect(sameWidthRendered.binds.map(\.description) == ["3"])
    }

    @Test func conditionAnyEmptyReturnsNone() {
        let predicate: Expr<Bool?>? = Condition.any.predicate
        #expect(predicate == nil)
    }

    @Test func conditionAllEmptyReturnsNone() {
        let predicate: Expr<Bool?>? = Condition.all.predicate
        #expect(predicate == nil)
    }

    @Test func compilesConditionAnyOr() throws {
        var condition = Condition.any
        condition.add(CompilerUserModel.email.like("%example%"))
        condition.add(CompilerUserModel.id > 10)
        let predicate: Expr<Bool?> = try #require(condition.predicate)

        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE ("users"."email" LIKE $1 OR "users"."id" > $2)"#)
        #expect(rendered.binds.map(\.description) == ["%example%", "10"])
    }

    @Test func compilesConditionAllAnd() throws {
        var condition = Condition.all
        condition.add(CompilerUserModel.id > 10)
        condition.add(CompilerUserModel.email.like("%example%"))
        let predicate: Expr<Bool?> = try #require(condition.predicate)

        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE ("users"."id" > $1 AND "users"."email" LIKE $2)"#)
        #expect(rendered.binds.map(\.description) == ["10", "%example%"])
    }

    @Test func conditionPreservesSingleNullablePredicateType() throws {
        var condition = Condition.all
        condition.add(CompilerUserModel.email == "a@b.com")
        let predicate: Expr<Bool?> = try #require(condition.predicate)

        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."email" = $1"#)
        #expect(rendered.binds.map(\.description) == ["a@b.com"])
    }

    /// `??` is rust-dbkit's `func::coalesce` here. Each use of `nullableRHS` binds its value again.
    @Test func compilesOrderedComparisonsWithNullableRHSExpressions() {
        let nullableRHS: Expr<Int64?> = CompilerUserModel.score + 1
        let requiredRHS: Expr<Int64> = CompilerUserModel.id + 1
        let less: Expr<Bool?> = CompilerUserModel.id < nullableRHS
        let lessOrEqual: Expr<Bool?> = CompilerUserModel.id <= nullableRHS
        let greater: Expr<Bool?> = CompilerUserModel.id > nullableRHS
        let greaterOrEqual: Expr<Bool?> = CompilerUserModel.id >= nullableRHS
        let nullableLeft: Expr<Bool?> = CompilerUserModel.score < requiredRHS
        let required: Expr<Bool> = CompilerUserModel.id < requiredRHS
        let coalesced: Expr<Bool> = CompilerUserModel.id < (CompilerUserModel.score ?? 0)

        let query: Projection<Bool?, Bool?, Bool?, Bool?, Bool?, Bool, Bool> = CompilerUserModel.query()
            .select(
                less.as("less"),
                lessOrEqual.as("less_or_equal"),
                greater.as("greater"),
                greaterOrEqual.as("greater_or_equal"),
                nullableLeft.as("nullable_left"),
                required.as("required"),
                coalesced.as("coalesced")
            )
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT "users"."id" < ("users"."score" + $1) AS "less", "users"."id" <= ("users"."score" + $2) AS "less_or_equal", "users"."id" > ("users"."score" + $3) AS "greater", "users"."id" >= ("users"."score" + $4) AS "greater_or_equal", "users"."score" < ("users"."id" + $5) AS "nullable_left", "users"."id" < ("users"."id" + $6) AS "required", "users"."id" < COALESCE("users"."score", $7) AS "coalesced" FROM "users""#
        )
        #expect(rendered.binds.map(\.description) == ["1", "1", "1", "1", "1", "1", "0"])
    }

    @Test func compilesNullableValueComparisonProjections() {
        let equals: Expr<Bool?> = CompilerUserModel.email == "a@b.com"
        let differs: Expr<Bool?> = CompilerUserModel.email != "blocked@example.com"
        let inRange: Expr<Bool?> = CompilerUserModel.score.between(1, 10)
        let matches: Expr<Bool?> = CompilerUserModel.email.like("%@example.com")
        let matchesCaseInsensitively: Expr<Bool?> = CompilerUserModel.email.ilike("%@EXAMPLE.COM")
        let listed: Expr<Bool?> = CompilerUserModel.email.in(["a@b.com", "c@d.com"])
        let emptyList: Expr<Bool?> = CompilerUserModel.email.in([])

        let rendered = CompilerUserModel.query()
            .select(
                equals.as("equals"),
                differs.as("differs"),
                inRange.as("in_range"),
                matches.as("matches"),
                matchesCaseInsensitively.as("matches_case_insensitively"),
                listed.as("listed"),
                emptyList.as("empty_list")
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "users"."email" = $1 AS "equals", "users"."email" <> $2 AS "differs", "users"."score" BETWEEN $3 AND $4 AS "in_range", "users"."email" LIKE $5 AS "matches", "users"."email" ILIKE $6 AS "matches_case_insensitively", "users"."email" IN ($7, $8) AS "listed", FALSE AS "empty_list" FROM "users""#
        )
        #expect(
            rendered.binds.map(\.description) == [
                "a@b.com", "blocked@example.com", "1", "10", "%@example.com", "%@EXAMPLE.COM", "a@b.com", "c@d.com",
            ])
    }

    @Test func compilesSelectOnlyWithColumns() {
        let query: Projection<String?, Int64> = CompilerUserModel.query().select(CompilerUserModel.email, CompilerUserModel.id)
        let rendered = query.render()
        #expect(rendered.sql == #"SELECT "users"."email", "users"."id" FROM "users""#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesSelectOnlyWithColumnAs() {
        let query: Projection<String?> = CompilerUserModel.query().select(CompilerUserModel.email.as("email_addr"))
        let rendered = query.render()
        #expect(rendered.sql == #"SELECT "users"."email" AS "email_addr" FROM "users""#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesDivisionExpressionsWithStableParentheses() {
        let rate: Expr<Double> = SaleModel.amount.cast(to: Double.self) / SaleModel.id
        let rendered = SaleModel.query()
            .select(rate.as("rate"))
            .filter((SaleModel.amount / SaleModel.id) / 2 > 3)
            .orderBy(rate.desc)
            .limit(10)
            .offset(5)
            .render()
        #expect(
            rendered.sql
                == #"SELECT (CAST("sales"."amount" AS double precision) / "sales"."id") AS "rate" FROM "sales" WHERE (("sales"."amount" / "sales"."id") / $1) > $2 ORDER BY (CAST("sales"."amount" AS double precision) / "sales"."id") DESC LIMIT 10 OFFSET 5"#
        )
        #expect(rendered.binds.map(\.description) == ["2", "3"])
    }

    @Test func compilesFloat8CastsForColumnsComputedAndAggregateExpressions() {
        let nullableScore: Expr<Double?> = CompilerUserModel.score.cast(to: Double.self)
        let computed: Expr<Double?> = (CompilerUserModel.score + 5).cast(to: Double.self)

        let users = CompilerUserModel.query().select(nullableScore.as("score"), computed.as("adjusted_score")).render()
        #expect(
            users.sql
                == #"SELECT CAST("users"."score" AS double precision) AS "score", CAST(("users"."score" + $1) AS double precision) AS "adjusted_score" FROM "users""#
        )
        #expect(users.binds.map(\.description) == ["5"])

        let aggregate: Expr<Double?> = SQL.sum(SaleModel.amount).cast(to: Double.self)
        let sales = SaleModel.query().select(aggregate.as("total")).render()
        #expect(sales.sql == #"SELECT CAST(SUM("sales"."amount") AS double precision) AS "total" FROM "sales""#)
        #expect(sales.binds.isEmpty)
    }

    @Test func compilesFilteredAggregateCastWithFilterInsideCast() {
        let aggregate: Expr<Double?> = SQL.sum(SaleModel.amount).filter(SaleModel.region == "us").cast(to: Double.self)
        let rendered = SaleModel.query().select(aggregate.as("total")).render()
        #expect(
            rendered.sql
                == #"SELECT CAST(SUM("sales"."amount") FILTER (WHERE "sales"."region" = $1) AS double precision) AS "total" FROM "sales""#
        )
        #expect(rendered.binds.map(\.description) == ["us"])
    }

    /// rust-dbkit selects `email` without an alias, which `select` can't mix with aliased expressions, so it is aliased
    /// `email`.
    @Test func compilesGroupByAndHaving() {
        let query: Projection<String?, Int64> = CompilerUserModel.query()
            .select(CompilerUserModel.email.as("email"), SQL.count(CompilerUserModel.id).as("cnt"))
            .groupBy(CompilerUserModel.email)
            .having(SQL.count(CompilerUserModel.id) > 1)
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT "users"."email" AS "email", COUNT("users"."id") AS "cnt" FROM "users" GROUP BY "users"."email" HAVING COUNT("users"."id") > $1"#
        )
        #expect(rendered.binds.map(\.description) == ["1"])
    }

    @Test func compilesFilteredAggregateProjectionsWithoutGroupBy() {
        let discountedUSSale: Expr<Bool> = SaleModel.region == "us" && SaleModel.amount <= 50
        let query: Projection<Int64, Int64, Date?, Int64> = SaleModel.query()
            .select(
                SQL.count(SaleModel.id).as("active_sales"),
                SQL.count(SaleModel.id).filter(discountedUSSale).as("discounted_us_sales"),
                SQL.min(SaleModel.createdAt).filter(discountedUSSale).as("oldest_discounted_us_sale_at"),
                SQL.count(SaleModel.id).filter(SaleModel.region == "missing").as("missing_sales")
            )
            .filter(SaleModel.amount > 0)
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT COUNT("sales"."id") AS "active_sales", COUNT("sales"."id") FILTER (WHERE ("sales"."region" = $1 AND "sales"."amount" <= $2)) AS "discounted_us_sales", MIN("sales"."created_at") FILTER (WHERE ("sales"."region" = $3 AND "sales"."amount" <= $4)) AS "oldest_discounted_us_sale_at", COUNT("sales"."id") FILTER (WHERE "sales"."region" = $5) AS "missing_sales" FROM "sales" WHERE "sales"."amount" > $6"#
        )
        #expect(rendered.binds.map(\.description) == ["us", "50", "us", "50", "missing", "0"])
    }

    @Test func compilesFilteredAggregateInGroupedProjectionAndHaving() {
        let query: Projection<String, Int64> = SaleModel.query()
            .select(SaleModel.region.as("region"), SQL.count(SaleModel.id).filter(SaleModel.amount >= 50).as("large_sales"))
            .groupBy(SaleModel.region)
            .having(SQL.count(SaleModel.id).filter(SaleModel.amount >= 50) > 1)
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT "sales"."region" AS "region", COUNT("sales"."id") FILTER (WHERE "sales"."amount" >= $1) AS "large_sales" FROM "sales" GROUP BY "sales"."region" HAVING COUNT("sales"."id") FILTER (WHERE "sales"."amount" >= $2) > $3"#
        )
        #expect(rendered.binds.map(\.description) == ["50", "50", "1"])
    }

    /// `??` is rust-dbkit's `func::coalesce` here.
    @Test func compilesScalarFunctionWrappingFilteredAggregate() {
        let usTotal: Expr<Decimal> = SQL.sum(SaleModel.amount).filter(SaleModel.region == "us") ?? 0
        let rendered = SaleModel.query().select(usTotal.as("us_total")).render()
        #expect(
            rendered.sql
                == #"SELECT COALESCE(SUM("sales"."amount") FILTER (WHERE "sales"."region" = $1), $2) AS "us_total" FROM "sales""#
        )
        #expect(rendered.binds.map(\.description) == ["us", "0"])
    }

    /// PostgreSQL sums `bigint` as `numeric`, so the sums are `Decimal` where rust-dbkit types them `i64`. `??` is
    /// rust-dbkit's `func::coalesce` here.
    @Test func compilesNullableSumAndNonNullCoalesce() {
        let total: AggregateExpr<Decimal?> = SQL.sum(SaleModel.amount)
        let filteredTotal: Expr<Decimal?> = SQL.sum(SaleModel.amount).filter(SaleModel.region == "us")
        let guaranteedTotal: Expr<Decimal> = SQL.sum(SaleModel.amount) ?? 0
        let query: Projection<Decimal?, Decimal?, Decimal> = SaleModel.query()
            .select(total.as("total"), filteredTotal.as("filtered_total"), guaranteedTotal.as("guaranteed_total"))
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT SUM("sales"."amount") AS "total", SUM("sales"."amount") FILTER (WHERE "sales"."region" = $1) AS "filtered_total", COALESCE(SUM("sales"."amount"), $2) AS "guaranteed_total" FROM "sales""#
        )
        #expect(rendered.binds.map(\.description) == ["us", "0"])
    }

    @Test func compilesMinMaxAggregateProjections() {
        let query: Projection<String, Date?, Date?, Int64?, Int64?> = SaleModel.query()
            .select(
                SaleModel.region.as("region"),
                SQL.min(SaleModel.createdAt).as("first_sale_at"),
                SQL.max(SaleModel.createdAt).as("last_sale_at"),
                SQL.min(SaleModel.amount).as("min_amount"),
                SQL.max(SaleModel.amount).as("max_amount")
            )
            .groupBy(SaleModel.region)
            .having(SQL.max(SaleModel.amount) > 100)
            .orderBy(SQL.min(SaleModel.createdAt).asc)
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT "sales"."region" AS "region", MIN("sales"."created_at") AS "first_sale_at", MAX("sales"."created_at") AS "last_sale_at", MIN("sales"."amount") AS "min_amount", MAX("sales"."amount") AS "max_amount" FROM "sales" GROUP BY "sales"."region" HAVING MAX("sales"."amount") > $1 ORDER BY MIN("sales"."created_at") ASC"#
        )
        #expect(rendered.binds.map(\.description) == ["100"])
    }

    @Test func compilesMinMaxForNullableTextWithoutNestedOptionType() {
        let minBody: AggregateExpr<String?> = SQL.min(CompilerTextSampleModel.body)
        let maxBody: AggregateExpr<String?> = SQL.max(CompilerTextSampleModel.body)
        let query: Projection<String?, String?> = CompilerTextSampleModel.query().select(minBody.as("min_body"), maxBody.as("max_body"))
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT MIN("text_samples"."body") AS "min_body", MAX("text_samples"."body") AS "max_body" FROM "text_samples""#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesArithmeticExpressionInProjectionAndOrdering() {
        let rendered = SaleModel.query()
            .select((SaleModel.amount + SaleModel.id).as("projected_total"))
            .orderBy((SaleModel.amount - 10).desc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT ("sales"."amount" + "sales"."id") AS "projected_total" FROM "sales" ORDER BY ("sales"."amount" - $1) DESC"#
        )
        #expect(rendered.binds.map(\.description) == ["10"])
    }

    /// rust-dbkit types two `smallint`s added as `Expr<i32>`; they stay `Expr<Int16>` here, as in PostgreSQL. The SQL is
    /// the same.
    @Test func compilesSmallintArithmeticProjectionWithIntegerExpressionType() {
        let projectedTotal: Expr<Int16> = CompilerCompactRowModel.leftUnits + CompilerCompactRowModel.rightUnits
        let projectedDelta: Expr<Int16> = CompilerCompactRowModel.leftUnits - CompilerCompactRowModel.rightUnits
        let rendered = CompilerCompactRowModel.query()
            .select(projectedTotal.as("total_units"))
            .orderBy(projectedDelta.desc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT ("compact_rows"."left_units" + "compact_rows"."right_units") AS "total_units" FROM "compact_rows" ORDER BY ("compact_rows"."left_units" - "compact_rows"."right_units") DESC"#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesPowerWithNullableNumericColumn() {
        let powered: Expr<Double?> = SQL.power(CompilerUserModel.score, Int64(2))
        let rendered = CompilerUserModel.query().select(powered.as("powered")).render()
        #expect(rendered.sql == #"SELECT POWER("users"."score", $1) AS "powered" FROM "users""#)
        #expect(rendered.binds.map(\.description) == ["2"])
    }

    @Test func compilesGreatestAndLeastWithNullableOperands() {
        let lowerBounded: Expr<Int64> = SQL.greatest(CompilerUserModel.score, 0)
        let upperBounded: Expr<Int64> = SQL.least(100, CompilerUserModel.score)
        let nullable: Expr<Int64?> = SQL.greatest(CompilerUserModel.score, CompilerUserModel.score)
        let rendered = CompilerUserModel.query()
            .select(lowerBounded.as("lower_bounded"), upperBounded.as("upper_bounded"), nullable.as("nullable"))
            .render()
        #expect(
            rendered.sql
                == #"SELECT GREATEST("users"."score", $1) AS "lower_bounded", LEAST($2, "users"."score") AS "upper_bounded", GREATEST("users"."score", "users"."score") AS "nullable" FROM "users""#
        )
        #expect(rendered.binds.map(\.description) == ["0", "100"])
    }

    @Test func compilesUpperFunctionFilter() {
        let predicate: Expr<Bool?> = SQL.upper(CompilerUserModel.email) == "TEST"
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE UPPER("users"."email") = $1"#)
        #expect(rendered.binds.map(\.description) == ["TEST"])
    }

    @Test func compilesLowerFunctionWithLiteralInput() {
        let lowered: Expr<String> = SQL.lower("MiXeD")
        let rendered = CompilerTextSampleModel.query().select(lowered.as("lowered")).render()
        #expect(rendered.sql == #"SELECT LOWER($1) AS "lowered" FROM "text_samples""#)
        #expect(rendered.binds.map(\.description) == ["MiXeD"])
    }

    /// rust-dbkit binds the unit, which takes any text. `DateTruncUnit` renders as a literal, so the same expression in
    /// a select list and in `GROUP BY` renders the same.
    @Test func compilesDateTruncFunctionFilter() throws {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let rendered = EventModel.query().filter(SQL.dateTrunc(.day, EventModel.startsAt) == day).render()
        #expect(rendered.sql == #"SELECT "events".* FROM "events" WHERE DATE_TRUNC('day', "events"."starts_at") = $1"#)
        try #require(rendered.binds.count == 1)
        #expect(rendered.binds[0].value as? Date == day)
    }

    @Test func compilesNestedFunctions() {
        let predicate: Expr<Bool> = SQL.upper(SQL.coalesce(CompilerUserModel.email, "unknown")) == "ALPHA"
        let rendered = CompilerUserModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE UPPER(COALESCE("users"."email", $1)) = $2"#)
        #expect(rendered.binds.map(\.description) == ["unknown", "ALPHA"])
    }

    @Test func compilesTrimFunctionFilter() {
        let predicate: Expr<Bool> = SQL.trim(CompilerTextSampleModel.title) == "alpha"
        let rendered = CompilerTextSampleModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "text_samples".* FROM "text_samples" WHERE TRIM("text_samples"."title") = $1"#)
        #expect(rendered.binds.map(\.description) == ["alpha"])
    }

    @Test func compilesSelectOnlyWithFuncColumn() {
        let query: Projection<String?> = CompilerUserModel.query().select(SQL.upper(CompilerUserModel.email))
        let rendered = query.render()
        #expect(rendered.sql == #"SELECT UPPER("users"."email") FROM "users""#)
        #expect(rendered.binds.isEmpty)
    }

    /// rust-dbkit selects `users.id` without an alias next to the aliased count; a projection names all its columns
    /// or none.
    @Test func compilesSelectOnlyWithJoinAndGroupBy() {
        let query: Projection<Int64, Int64> = CompilerUserModel.query()
            .select(CompilerUserModel.id.as("id"), SQL.count(TodoModel.id).as("todo_count"))
            .join(TodoModel.self, on: CompilerUserModel.id == TodoModel.userID)
            .groupBy(CompilerUserModel.id)
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT "users"."id" AS "id", COUNT("todos"."id") AS "todo_count" FROM "users" JOIN "todos" ON "users"."id" = "todos"."user_id" GROUP BY "users"."id""#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesGroupByExpression() {
        let query: Projection<Date, Decimal?> = SaleModel.query()
            .select(SQL.dateTrunc(.day, SaleModel.createdAt).as("bucket"), SQL.sum(SaleModel.amount).as("total"))
            .groupBy(SQL.dateTrunc(.day, SaleModel.createdAt))
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT DATE_TRUNC('day', "sales"."created_at") AS "bucket", SUM("sales"."amount") AS "total" FROM "sales" GROUP BY DATE_TRUNC('day', "sales"."created_at")"#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesOrderByExpression() {
        let rendered = SaleModel.query()
            .select(SQL.dateTrunc(.day, SaleModel.createdAt).as("bucket"))
            .orderBy(SQL.dateTrunc(.day, SaleModel.createdAt).desc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT DATE_TRUNC('day', "sales"."created_at") AS "bucket" FROM "sales" ORDER BY DATE_TRUNC('day', "sales"."created_at") DESC"#
        )
        #expect(rendered.binds.isEmpty)
    }

    /// rust-dbkit renders `between` as `>=` and `<=`.
    @Test func compilesBetweenOnFuncExpression() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_000_100)
        let predicate: Expr<Bool> = SQL.dateTrunc(.day, SaleModel.createdAt).between(start, end)
        let rendered = SaleModel.query().filter(predicate).render()
        #expect(
            rendered.sql == #"SELECT "sales".* FROM "sales" WHERE DATE_TRUNC('day', "sales"."created_at") BETWEEN $1 AND $2"#)
        #expect(rendered.binds.map { $0.value as? Date } == [start, end])
    }

    @Test func compilesNestedCharLengthTrimFilterOnNullableText() {
        let predicate: Expr<Bool?> = SQL.charLength(SQL.trim(TS.body)) >= 5
        let rendered = TS.query().filter(TS.body.isNotNull).filter(predicate).render()
        #expect(
            rendered.sql
                == #"SELECT "text_samples".* FROM "text_samples" WHERE "text_samples"."body" IS NOT NULL AND CHAR_LENGTH(TRIM("text_samples"."body")) >= $1"#
        )
        #expect(rendered.binds.map(\.description) == ["5"])
    }

    @Test func compilesByteAndBitLengthWithPostgresqlNames() {
        let literalBytes: Expr<Int32> = SQL.byteLength("é")
        let titleBytes: Expr<Int32> = SQL.byteLength(TS.title)
        let trimmedBodyBits: Expr<Int32?> = SQL.bitLength(SQL.trim(TS.body))
        let query: Projection<Int32, Int32, Int32?> = TS.query()
            .select(literalBytes.as("literal_bytes"), titleBytes.as("title_bytes"), trimmedBodyBits.as("trimmed_body_bits"))
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT OCTET_LENGTH($1) AS "literal_bytes", OCTET_LENGTH("text_samples"."title") AS "title_bytes", BIT_LENGTH(TRIM("text_samples"."body")) AS "trimmed_body_bits" FROM "text_samples""#
        )
        #expect(rendered.binds.map(\.description) == ["é"])
    }

    /// A nullable search text makes the position nullable, as a nullable prefix does.
    @Test func compilesPositionAndStartsWithWithExpressionArguments() {
        let normalizedPosition: Expr<Int32?> = SQL.position(SQL.lower(TS.title), SQL.trim(TS.body))
        let normalizedPrefix: Expr<Bool?> = SQL.startsWith(SQL.lower(TS.title), SQL.lower(TS.body))
        let rendered = TS.query()
            .select(normalizedPosition.as("normalized_position"), normalizedPrefix.as("normalized_prefix"))
            .render()
        #expect(
            rendered.sql
                == #"SELECT STRPOS(LOWER("text_samples"."title"), TRIM("text_samples"."body")) AS "normalized_position", STARTS_WITH(LOWER("text_samples"."title"), LOWER("text_samples"."body")) AS "normalized_prefix" FROM "text_samples""#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesStringSearchAndLengthsInProjectionsFiltersAndOrderings() {
        let unsafeSearch = "'%_\\needle"
        let rendered = TS.query()
            .select(
                SQL.byteLength(TS.body).as("body_bytes"),
                SQL.bitLength(TS.title).as("title_bits"),
                SQL.position(TS.title, unsafeSearch).as("unsafe_position"),
                SQL.startsWith(TS.title, unsafeSearch).as("unsafe_prefix")
            )
            .filter(SQL.startsWith(TS.title, "prefix") == true)
            .filter(SQL.position(TS.title, "needle") > 0)
            .orderBy(SQL.byteLength(TS.body).desc)
            .orderBy(SQL.position(TS.title, "needle").asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT OCTET_LENGTH("text_samples"."body") AS "body_bytes", BIT_LENGTH("text_samples"."title") AS "title_bits", STRPOS("text_samples"."title", $1) AS "unsafe_position", STARTS_WITH("text_samples"."title", $2) AS "unsafe_prefix" FROM "text_samples" WHERE STARTS_WITH("text_samples"."title", $3) = $4 AND STRPOS("text_samples"."title", $5) > $6 ORDER BY OCTET_LENGTH("text_samples"."body") DESC, STRPOS("text_samples"."title", $7) ASC"#
        )
        #expect(rendered.binds.map(\.description) == [unsafeSearch, unsafeSearch, "prefix", "true", "needle", "0", "needle"])
    }

    /// rust-dbkit selects `id` without an alias, which `select` can't mix with aliased expressions, so it is aliased `id`.
    @Test func compilesTrimmedNullableTextSelection() {
        let query: Projection<Int64, String?, Int32?> = TS.query()
            .select(
                TS.id.as("id"),
                SQL.trim(TS.body).as("trimmed_body"),
                SQL.charLength(SQL.trim(TS.body)).as("trimmed_body_len")
            )
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT "text_samples"."id" AS "id", TRIM("text_samples"."body") AS "trimmed_body", CHAR_LENGTH(TRIM("text_samples"."body")) AS "trimmed_body_len" FROM "text_samples""#
        )
        #expect(rendered.binds.isEmpty)
    }

    /// "Normalization" here is trimming and case conversion, not Unicode normalization.
    @Test func compilesStringNormalizationInProjectionsFilterAndOrdering() {
        let trimmedBody: Expr<String?> = SQL.trimEndChars(TS.body, "!?")
        let rendered = TS.query()
            .select(
                SQL.lower(TS.title).as("lowered_title"),
                SQL.trimChars(TS.title, "xy").as("trimmed_title"),
                SQL.trimStart(TS.title).as("left_trimmed_title"),
                SQL.trimStartChars(TS.title, "@").as("handle"),
                SQL.trimEnd(TS.body).as("right_trimmed_body"),
                trimmedBody.as("punctuation_trimmed_body")
            )
            .filter(SQL.trimChars(TS.title, ".") == "alpha")
            .orderBy(SQL.trimStartChars(TS.title, "#").asc)
            .orderBy(SQL.trimEnd(TS.body).desc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT LOWER("text_samples"."title") AS "lowered_title", TRIM(BOTH $1 FROM "text_samples"."title") AS "trimmed_title", TRIM(LEADING FROM "text_samples"."title") AS "left_trimmed_title", TRIM(LEADING $2 FROM "text_samples"."title") AS "handle", TRIM(TRAILING FROM "text_samples"."body") AS "right_trimmed_body", TRIM(TRAILING $3 FROM "text_samples"."body") AS "punctuation_trimmed_body" FROM "text_samples" WHERE TRIM(BOTH $4 FROM "text_samples"."title") = $5 ORDER BY TRIM(LEADING $6 FROM "text_samples"."title") ASC, TRIM(TRAILING FROM "text_samples"."body") DESC"#
        )
        #expect(rendered.binds.map(\.description) == ["xy", "@", "!?", ".", "alpha", "#"])
    }

    @Test func customTrimCharactersAreBoundInSQLOrder() {
        let predicate: Expr<Bool> = SQL.trimChars(SQL.trimStartChars(TS.title, "'\\"), "[]") == "alpha"
        let rendered = TS.query().filter(predicate).render()
        #expect(
            rendered.sql
                == #"SELECT "text_samples".* FROM "text_samples" WHERE TRIM(BOTH $1 FROM TRIM(LEADING $2 FROM "text_samples"."title")) = $3"#
        )
        #expect(rendered.binds.map(\.description) == ["[]", "'\\", "alpha"])
    }

    @Test func compilesNormalizedHandleLookup() {
        let handle = "alice"
        let normalized: Expr<String> = SQL.lower(SQL.trim(SQL.trimStartChars(SQL.trim(TS.title), "@")))
        let rendered = TS.query().filter(normalized == handle).render()
        #expect(
            rendered.sql
                == #"SELECT "text_samples".* FROM "text_samples" WHERE LOWER(TRIM(TRIM(LEADING $1 FROM TRIM("text_samples"."title")))) = $2"#
        )
        #expect(rendered.binds.map(\.description) == ["@", handle])
    }

    /// Counts take an `Int32` value or expression, also mixed in one call.
    @Test func compilesStringExtractionAndSizingFunctionsWithExpectedTypes() {
        let leftTitle: Expr<String> = SQL.left(TS.title, 2)
        let rightBody: Expr<String?> = SQL.right(TS.body, TS.width)
        let substringTitle: Expr<String> = SQL.substring(SQL.lower(TS.title), 2, TS.width)
        let repeatedLiteral: Expr<String> = SQL.repeat("ab", 3)
        let paddedTitle: Expr<String> = SQL.padStart(TS.title, 8, "xy")
        let paddedBody: Expr<String?> = SQL.padEnd(TS.body, SQL.charLength(TS.title), SQL.lower("Z"))

        let query: Projection<String, String?, String, String, String, String?> = TS.query()
            .select(
                leftTitle.as("left_title"),
                rightBody.as("right_body"),
                substringTitle.as("substring_title"),
                repeatedLiteral.as("repeated_literal"),
                paddedTitle.as("padded_title"),
                paddedBody.as("padded_body")
            )
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT LEFT("text_samples"."title", $1) AS "left_title", RIGHT("text_samples"."body", "text_samples"."width") AS "right_body", SUBSTRING(LOWER("text_samples"."title"), $2, "text_samples"."width") AS "substring_title", REPEAT($3, $4) AS "repeated_literal", LPAD("text_samples"."title", $5, $6) AS "padded_title", RPAD("text_samples"."body", CHAR_LENGTH("text_samples"."title"), LOWER($7)) AS "padded_body" FROM "text_samples""#
        )
        #expect(rendered.binds.map(\.description) == ["2", "2", "ab", "3", "8", "xy", "Z"])
    }

    /// A nullable count, start, length or index makes the result nullable, as PostgreSQL returns NULL for it.
    @Test func compilesStringFunctionsWithNullableNumericArguments() {
        let left: Expr<String?> = SQL.left(TS.title, TS.optionalWidth)
        let right: Expr<String?> = SQL.right(TS.title, TS.optionalWidth)
        let substringStart: Expr<String?> = SQL.substring(TS.title, TS.optionalWidth, TS.width)
        let substringCount: Expr<String?> = SQL.substring(TS.title, TS.width, TS.optionalWidth)
        let repeated: Expr<String?> = SQL.repeat(TS.title, TS.optionalWidth)
        let paddedStart: Expr<String?> = SQL.padStart(TS.title, TS.optionalWidth, "x")
        let paddedEnd: Expr<String?> = SQL.padEnd(TS.body, TS.optionalWidth, "x")
        let replacedStart: Expr<String?> = SQL.replaceRange(TS.title, "X", TS.optionalWidth, TS.width)
        let replacedCount: Expr<String?> = SQL.replaceRange(TS.title, "X", TS.width, TS.optionalWidth)
        let part: Expr<String?> = SQL.splitPart(TS.title, ",", TS.optionalWidth)

        let rendered = TS.query()
            .select(
                left.as("left_value"),
                right.as("right_value"),
                substringStart.as("substring_start"),
                substringCount.as("substring_count"),
                repeated.as("repeated"),
                paddedStart.as("padded_start"),
                paddedEnd.as("padded_end"),
                replacedStart.as("replaced_start"),
                replacedCount.as("replaced_count"),
                part.as("part")
            )
            .filter(SQL.left(TS.title, TS.optionalWidth) == "ab")
            .render()
        #expect(
            rendered.sql
                == #"SELECT LEFT("text_samples"."title", "text_samples"."optional_width") AS "left_value", RIGHT("text_samples"."title", "text_samples"."optional_width") AS "right_value", SUBSTRING("text_samples"."title", "text_samples"."optional_width", "text_samples"."width") AS "substring_start", SUBSTRING("text_samples"."title", "text_samples"."width", "text_samples"."optional_width") AS "substring_count", REPEAT("text_samples"."title", "text_samples"."optional_width") AS "repeated", LPAD("text_samples"."title", "text_samples"."optional_width", $1) AS "padded_start", RPAD("text_samples"."body", "text_samples"."optional_width", $2) AS "padded_end", OVERLAY("text_samples"."title", $3, "text_samples"."optional_width", "text_samples"."width") AS "replaced_start", OVERLAY("text_samples"."title", $4, "text_samples"."width", "text_samples"."optional_width") AS "replaced_count", SPLIT_PART("text_samples"."title", $5, "text_samples"."optional_width") AS "part" FROM "text_samples" WHERE LEFT("text_samples"."title", "text_samples"."optional_width") = $6"#
        )
        #expect(rendered.binds.map(\.description) == ["x", "x", "X", "X", ",", "ab"])
    }

    @Test func compilesNestedStringFunctionsInProjectionFilterAndOrdering() {
        let fill = "'%_\\"
        let query: Projection<String> = TS.query()
            .select(SQL.substring(SQL.left(SQL.lower(TS.title), 5), 2, 3).as("slice"))
            .filter(SQL.repeat(SQL.right(SQL.trim(TS.title), 2), 2) == "abab")
            .orderBy(SQL.padEnd(SQL.left(TS.body, 4), 8, fill).asc)
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT SUBSTRING(LEFT(LOWER("text_samples"."title"), $1), $2, $3) AS "slice" FROM "text_samples" WHERE REPEAT(RIGHT(TRIM("text_samples"."title"), $4), $5) = $6 ORDER BY RPAD(LEFT("text_samples"."body", $7), $8, $9) ASC"#
        )
        #expect(rendered.binds.map(\.description) == ["5", "2", "3", "2", "2", "abab", "4", "8", fill])
    }

    /// A nullable text in any argument makes the result nullable.
    @Test func compilesTextTransformationFunctionsWithExpectedTypesAndPostgresqlNames() {
        let titled: Expr<String> = SQL.titleCase(TS.title)
        let reversed: Expr<String?> = SQL.reverse(TS.body)
        let replaced: Expr<String> = SQL.replace(SQL.lower(TS.title), "FROM_LITERAL", "TO_LITERAL")
        let nullableReplace: Expr<String?> = SQL.replace(TS.title, TS.body, "fallback")
        let ranged: Expr<String> = SQL.replaceRange(TS.title, SQL.upper("replacement"), TS.width, 2)
        let nullableRange: Expr<String?> = SQL.replaceRange(TS.title, TS.body, 1, TS.width)
        let translated: Expr<String> = SQL.translateChars(TS.title, "abc", "xyz")
        let nullableTranslation: Expr<String?> = SQL.translateChars(TS.title, "abc", TS.body)

        let rendered = TS.query()
            .select(
                titled.as("titled"),
                reversed.as("reversed"),
                replaced.as("replaced"),
                nullableReplace.as("nullable_replace"),
                ranged.as("ranged"),
                nullableRange.as("nullable_range"),
                translated.as("translated"),
                nullableTranslation.as("nullable_translation")
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT INITCAP("text_samples"."title") AS "titled", REVERSE("text_samples"."body") AS "reversed", REPLACE(LOWER("text_samples"."title"), $1, $2) AS "replaced", REPLACE("text_samples"."title", "text_samples"."body", $3) AS "nullable_replace", OVERLAY("text_samples"."title", UPPER($4), "text_samples"."width", $5) AS "ranged", OVERLAY("text_samples"."title", "text_samples"."body", $6, "text_samples"."width") AS "nullable_range", TRANSLATE("text_samples"."title", $7, $8) AS "translated", TRANSLATE("text_samples"."title", $9, "text_samples"."body") AS "nullable_translation" FROM "text_samples""#
        )
        #expect(
            rendered.binds.map(\.description) == [
                "FROM_LITERAL", "TO_LITERAL", "fallback", "replacement", "2", "1", "abc", "xyz", "abc",
            ])
    }

    @Test func textTransformationArgumentsRemainBoundWhenComposed() {
        let unsafeText = "'%_\\[]().*+"
        let transformed = SQL.reverse(SQL.translateChars(SQL.replace(TS.title, unsafeText, "<$&>"), "[]", "{}"))
        let rendered = TS.query()
            .select(SQL.titleCase(transformed).as("transformed"))
            .filter(SQL.replaceRange(TS.body, unsafeText, 1, 2) == "expected")
            .orderBy(SQL.reverse(SQL.translateChars(TS.body, "%_", "")).asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT INITCAP(REVERSE(TRANSLATE(REPLACE("text_samples"."title", $1, $2), $3, $4))) AS "transformed" FROM "text_samples" WHERE OVERLAY("text_samples"."body", $5, $6, $7) = $8 ORDER BY REVERSE(TRANSLATE("text_samples"."body", $9, $10)) ASC"#
        )
        #expect(
            rendered.binds.map(\.description) == [unsafeText, "<$&>", "[]", "{}", unsafeText, "1", "2", "expected", "%_", ""])
    }

    /// rust-dbkit passes the values as an array; here they are arguments. PostgreSQL has no `CONCAT()` without
    /// arguments, so no values render an empty `VARIADIC` array.
    @Test func compilesStringCompositionFunctionsWithVariadicExpressionArrays() {
        let separator = "'%_\\[](){}"
        let joined: Expr<String> = SQL.concat(TS.title, SQL.lower("SUFFIX"), SQL.trim(TS.title))
        let nullableInputsStillJoin: Expr<String> = SQL.concat(TS.body, SQL.lower(TS.body))
        let separated: Expr<String> = SQL.concatWithSeparator(separator, TS.title, SQL.lower("SUFFIX"))
        let nullableSeparator: Expr<String?> = SQL.concatWithSeparator(TS.body, TS.body, SQL.trim(TS.body))
        let emptyJoined: Expr<String> = SQL.concat()
        let emptySeparated: Expr<String> = SQL.concatWithSeparator("")

        let rendered = TS.query()
            .select(
                joined.as("joined"),
                nullableInputsStillJoin.as("nullable_inputs_still_join"),
                separated.as("separated"),
                nullableSeparator.as("nullable_separator"),
                emptyJoined.as("empty_joined"),
                emptySeparated.as("empty_separated")
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT CONCAT("text_samples"."title", LOWER($1), TRIM("text_samples"."title")) AS "joined", CONCAT("text_samples"."body", LOWER("text_samples"."body")) AS "nullable_inputs_still_join", CONCAT_WS($2, "text_samples"."title", LOWER($3)) AS "separated", CONCAT_WS("text_samples"."body", "text_samples"."body", TRIM("text_samples"."body")) AS "nullable_separator", CONCAT(VARIADIC ARRAY[]::TEXT[]) AS "empty_joined", CONCAT_WS($4, VARIADIC ARRAY[]::TEXT[]) AS "empty_separated" FROM "text_samples""#
        )
        #expect(rendered.binds.map(\.description) == ["SUFFIX", separator, "SUFFIX", ""])
    }

    /// A nullable delimiter doesn't make `split` nullable: PostgreSQL splits into characters for a NULL delimiter.
    @Test func compilesSplitFunctionsWithExactTypesAndBindOrder() {
        let delimiter = "'%_\\.*+?[](){}^$|"
        let parts: Expr<[String]> = SQL.split(TS.title, delimiter)
        let nullableParts: Expr<[String]?> = SQL.split(TS.body, SQL.lower("::"))
        let nullDelimiterParts: Expr<[String]> = SQL.split(TS.title, TS.body)
        let part: Expr<String> = SQL.splitPart(TS.title, delimiter, TS.width)
        let nullablePart: Expr<String?> = SQL.splitPart(TS.body, SQL.lower("::"), SQL.charLength(TS.title))

        let query: Projection<[String], [String]?, [String], String, String?> = TS.query()
            .select(
                parts.as("parts"),
                nullableParts.as("nullable_parts"),
                nullDelimiterParts.as("null_delimiter_parts"),
                part.as("part"),
                nullablePart.as("nullable_part")
            )
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT STRING_TO_ARRAY("text_samples"."title", $1) AS "parts", STRING_TO_ARRAY("text_samples"."body", LOWER($2)) AS "nullable_parts", STRING_TO_ARRAY("text_samples"."title", "text_samples"."body") AS "null_delimiter_parts", SPLIT_PART("text_samples"."title", $3, "text_samples"."width") AS "part", SPLIT_PART("text_samples"."body", LOWER($4), CHAR_LENGTH("text_samples"."title")) AS "nullable_part" FROM "text_samples""#
        )
        #expect(rendered.binds.map(\.description) == [delimiter, "::", delimiter, "::"])
    }

    @Test func composesStringSplittingInProjectionsFiltersAndOrderings() {
        let nested: Expr<String> = SQL.splitPart(SQL.concat(TS.title, SQL.lower("SUFFIX")), "::", 1)
        let rendered = TS.query()
            .select(SQL.split(SQL.lower(TS.title), "::").as("parts"), nested.as("first_part"))
            .filter(SQL.splitPart(TS.title, "::", 1) == "prefix")
            .filter(SQL.split(TS.title, "::") == ["prefix"])
            .orderBy(SQL.splitPart(TS.body, "::", TS.width).asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT STRING_TO_ARRAY(LOWER("text_samples"."title"), $1) AS "parts", SPLIT_PART(CONCAT("text_samples"."title", LOWER($2)), $3, $4) AS "first_part" FROM "text_samples" WHERE SPLIT_PART("text_samples"."title", $5, $6) = $7 AND STRING_TO_ARRAY("text_samples"."title", $8) = $9 ORDER BY SPLIT_PART("text_samples"."body", $10, "text_samples"."width") ASC"#
        )
        #expect(rendered.binds.map(\.description) == ["::", "SUFFIX", "::", "1", "::", "1", "prefix", "::", #"["prefix"]"#, "::"])
        #expect(rendered.binds[8].value as? [String] == ["prefix"])
    }

    /// The flags bind as PostgreSQL's flag string: `g` before `i`, and `''` for no flags. A nullable text, pattern or
    /// replacement makes the result nullable.
    @Test func compilesRegexReplaceWithOptionSetFlagsAndNullableTextArguments() {
        let replacedLiteral: Expr<String> = SQL.regexReplace("a1b22", #"\d+"#, "X", [.global, .caseInsensitive])
        let nullableSource: Expr<String?> = SQL.regexReplace(TS.body, #"\s+"#, " ", [])
        let nullablePattern: Expr<String?> = SQL.regexReplace(TS.title, TS.body, "X", [])
        let nullableReplacement: Expr<String?> = SQL.regexReplace(TS.title, "a", TS.body, .caseInsensitive)

        let rendered = TS.query()
            .select(
                replacedLiteral.as("replaced_literal"),
                nullableSource.as("nullable_source"),
                nullablePattern.as("nullable_pattern"),
                nullableReplacement.as("nullable_replacement")
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT REGEXP_REPLACE($1, $2, $3, $4) AS "replaced_literal", REGEXP_REPLACE("text_samples"."body", $5, $6, $7) AS "nullable_source", REGEXP_REPLACE("text_samples"."title", "text_samples"."body", $8, $9) AS "nullable_pattern", REGEXP_REPLACE("text_samples"."title", $10, "text_samples"."body", $11) AS "nullable_replacement" FROM "text_samples""#
        )
        #expect(rendered.binds.map(\.description) == ["a1b22", #"\d+"#, "X", "gi", #"\s+"#, " ", "", "X", "", "a", "i"])
    }

    /// A nullable text or pattern makes the result nullable.
    @Test func compilesRegexSplitWithOptionSetFlagsAndNullableTextArguments() {
        let splitLiteral: Expr<[String]> = SQL.regexSplit("a,b;c", "[,;]", [])
        let nullableSource: Expr<[String]?> = SQL.regexSplit(TS.body, #"\s+"#, .caseInsensitive)
        let nullablePattern: Expr<[String]?> = SQL.regexSplit(TS.title, TS.body, [])

        let rendered = TS.query()
            .select(splitLiteral.as("split_literal"), nullableSource.as("nullable_source"), nullablePattern.as("nullable_pattern"))
            .render()
        #expect(
            rendered.sql
                == #"SELECT REGEXP_SPLIT_TO_ARRAY($1, $2, $3) AS "split_literal", REGEXP_SPLIT_TO_ARRAY("text_samples"."body", $4, $5) AS "nullable_source", REGEXP_SPLIT_TO_ARRAY("text_samples"."title", "text_samples"."body", $6) AS "nullable_pattern" FROM "text_samples""#
        )
        #expect(rendered.binds.map(\.description) == ["a,b;c", "[,;]", "", #"\s+"#, "i", ""])
    }

    @Test func compilesNestedRegexTransformsInProjectionFilterAndOrderingWithBoundArguments() {
        let pattern = #"(['%_\\]+)"#
        let replacement = #"<\1>$1'%_\\"#
        let normalizedBody: Expr<String?> = SQL.regexReplace(
            SQL.lower(SQL.trim(SQL.substring(TS.body, 1, 99))), #"\s+"#, "-", .global)

        let rendered = TS.query()
            .select(
                SQL.regexReplace(SQL.lower(SQL.trim(TS.title)), SQL.lower(pattern), replacement, [.global, .caseInsensitive])
                    .as("replaced"),
                SQL.regexSplit(normalizedBody, pattern, []).as("parts")
            )
            .filter(normalizedBody == "aa-bb")
            .orderBy(SQL.regexSplit(SQL.trim(TS.body), #"\s+"#, []).asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT REGEXP_REPLACE(LOWER(TRIM("text_samples"."title")), LOWER($1), $2, $3) AS "replaced", REGEXP_SPLIT_TO_ARRAY(REGEXP_REPLACE(LOWER(TRIM(SUBSTRING("text_samples"."body", $4, $5))), $6, $7, $8), $9, $10) AS "parts" FROM "text_samples" WHERE REGEXP_REPLACE(LOWER(TRIM(SUBSTRING("text_samples"."body", $11, $12))), $13, $14, $15) = $16 ORDER BY REGEXP_SPLIT_TO_ARRAY(TRIM("text_samples"."body"), $17, $18) ASC"#
        )
        #expect(
            rendered.binds.map(\.description) == [
                pattern, replacement, "gi", "1", "99", #"\s+"#, "-", "g", pattern, "", "1", "99", #"\s+"#, "-", "g", "aa-bb",
                #"\s+"#, "",
            ])
    }
}
