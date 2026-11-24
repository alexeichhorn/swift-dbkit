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
}
