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
        // Waits for slice 14b: `SQL.sum(SaleModel.amount).cast(to: Double.self)` is `Expr<Double?>` and renders
        // `SELECT CAST(SUM("sales"."amount") AS double precision) AS "total" FROM "sales"`.
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
}
