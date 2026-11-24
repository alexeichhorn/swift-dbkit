import DBKit
import Foundation
import Testing

/// Numeric columns of each kind for the arithmetic rendering test.
@Model(table: "prices")
class PriceModel {
    @Key @AutoIncrement var id: Int64
    var quantity: Int32
    var minimum: Int32?
    var amount: Decimal
    var discount: Decimal?
    var rate: Double
}

/// Timestamp, interval and text columns for the interval rendering test.
@Model(table: "leases")
class LeaseModel {
    @Key @AutoIncrement var id: Int64
    var startsAt: Date
    var endsAt: Date?
    var term: Interval
    var grace: Interval?
    var note: String
}

@Suite struct SQLRenderingTests {
    @Test func filtersOrderingAndNullHandling() {
        let userID: Int64 = 7
        let note: String? = nil
        let rendered = TodoModel.query()
            .filter(TodoModel.userID == userID && TodoModel.note == nil)
            .filter(TodoModel.note == note || TodoModel.title.ilike("%milk%"))
            .orderBy(TodoModel.id.desc)
            .limit(20)
            .offset(40)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "todos".* FROM "todos" WHERE ("todos"."user_id" = $1 AND "todos"."note" IS NULL) AND ("todos"."note" IS NULL OR "todos"."title" ILIKE $2) ORDER BY "todos"."id" DESC LIMIT 20 OFFSET 40"#
        )
        #expect(rendered.binds.map(\.description) == ["7", "%milk%"])
    }

    @Test func eagerLoadingChangesTheRowType() {
        let users: Query<UserModel.Loaded<[TodoModel.Loaded<NotLoaded, [TagModel]>]>> = UserModel.query().with(\.todos) { $0.with(\.tags) }
        let todos: Query<TodoModel.Loaded<UserModel.Loaded<[TodoModel]>?, NotLoaded>> = TodoModel.query().with(\.user) { $0.with(\.todos) }
        // Waits for slice 18: `both`, `TodoModel.query().with(\.user, .joined).with(\.tags)` typed
        // `Query<TodoModel.Loaded<UserModel?, [TagModel]>>`, selecting the user's columns as `"user.id"`, `"user.name"`,
        // `"user.email"` and `"user.region"` through `LEFT JOIN "users" ON "users"."id" = "todos"."user_id"`.
        #expect(users.render().sql == #"SELECT "users".* FROM "users""#)
        #expect(todos.render().sql == #"SELECT "todos".* FROM "todos""#)
    }

    /// Select-in loads leave the main query as it is, before or after the other builders: each level of relations is
    /// fetched by a query of its own. Several relations load on one query and on one nested row.
    @Test func selectInLoadsKeepTheMainQuery() {
        let users: Query<UserModel.Loaded<[TodoModel.Loaded<UserModel?, [TagModel]>]>> = UserModel.query()
            .with(\.todos) { $0.with(\.user).with(\.tags, .selectIn) }
            .filter(UserModel.region == "eu")
            .orderBy(UserModel.name.asc)
            .limit(10)
        let rendered = users.render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" WHERE "users"."region" = $1 ORDER BY "users"."name" ASC LIMIT 10"#)
        #expect(rendered.binds.map(\.description) == ["eu"])

        let members: Query<MemberModel.Loaded<OrganizationModel?, MemberModel.Loaded<NotLoaded, MemberModel?>?>> = MemberModel.query()
            .with(\.organization)
            .with(\.manager) { $0.with(\.manager) }
        #expect(members.render().sql == #"SELECT "members".* FROM "members""#)
    }

    /// A comparison on a nullable column is `Expr<Bool?>`, and queries, updates and deletes filter by it.
    @Test func nullableComparisonsFilterQueriesUpdatesAndDeletes() {
        let isToday: Expr<Bool?> = TodoModel.note == "today"
        let isOpen: Expr<Bool> = !TodoModel.isComplete
        let todayOrOpen: Expr<Bool?> = isToday || isOpen
        let notToday: Expr<Bool?> = !isToday

        let query = TodoModel.query().filter(todayOrOpen).render()
        #expect(query.sql == #"SELECT "todos".* FROM "todos" WHERE ("todos"."note" = $1 OR NOT ("todos"."is_complete"))"#)
        #expect(query.binds.map(\.description) == ["today"])
        let update = TodoModel.update().set(TodoModel.note, to: nil).filter(isToday).render()
        #expect(update.sql == #"UPDATE "todos" SET "note" = NULL WHERE "todos"."note" = $1"#)
        #expect(update.binds.map(\.description) == ["today"])
        let delete = TodoModel.delete().filter(notToday).render()
        #expect(delete.sql == #"DELETE FROM "todos" WHERE NOT ("todos"."note" = $1)"#)
        #expect(delete.binds.map(\.description) == ["today"])
        // `IntegrationTests.projectionsDecodeByAliasAndNullableComparisonsAsOptionals` decodes such a projection.
        let selected: Projection<Bool?> = TodoModel.query().select(isToday)
        let projection = selected.render()
        #expect(projection.sql == #"SELECT "todos"."note" = $1 FROM "todos""#)
        #expect(projection.binds.map(\.description) == ["today"])
    }

    /// Projections take the builder methods of model queries, and `select` keeps what was built before it. Binds are
    /// numbered in the order of the SQL text, so the select list's come first.
    @Test func projectionsTakeTheQueryBuilders() {
        @Projection struct TodoSummary {
            let title: String
            let isToday: Bool?
        }
        let summaries: ProjectionQuery<TodoSummary> = TodoModel.query()
            .filter(TodoModel.userID == 7)
            .select(TodoSummary.columns(title: TodoModel.title, isToday: TodoModel.note == "today"))
            .filter(!TodoModel.isComplete)
            .distinct()
            .orderBy(TodoModel.title.asc)
            .limit(10)
            .offset(20)
        let rendered = summaries.render()
        #expect(
            rendered.sql
                == #"SELECT DISTINCT "todos"."title", "todos"."note" = $1 FROM "todos" WHERE "todos"."user_id" = $2 AND NOT ("todos"."is_complete") ORDER BY "todos"."title" ASC LIMIT 10 OFFSET 20"#
        )
        #expect(rendered.binds.map(\.description) == ["today", "7"])

        let owners: Projection<Int64, String?> = TodoModel.query()
            .select(TodoModel.userID.as("user_id"), TodoModel.note.as("note"))
            .distinct()
            .filter(TodoModel.isComplete)
            .orderBy(TodoModel.userID.desc)
            .limit(5)
            .offset(10)
        let ownersRendered = owners.render()
        #expect(
            ownersRendered.sql
                == #"SELECT DISTINCT "todos"."user_id" AS "user_id", "todos"."note" AS "note" FROM "todos" WHERE "todos"."is_complete" ORDER BY "todos"."user_id" DESC LIMIT 5 OFFSET 10"#
        )
        #expect(ownersRendered.binds.isEmpty)
    }

    @Test func nullChecksAndFallbacks() {
        let checked: Expr<Bool> = TodoModel.note.isNull || TodoModel.note.isNotNull
        let fallback: Expr<String> = TodoModel.note ?? TodoModel.title
        let rendered = TodoModel.query().filter(checked).filter(fallback == "milk").render()
        #expect(
            rendered.sql
                == #"SELECT "todos".* FROM "todos" WHERE ("todos"."note" IS NULL OR "todos"."note" IS NOT NULL) AND COALESCE("todos"."note", "todos"."title") = $1"#
        )
        #expect(rendered.binds.map(\.description) == ["milk"])
    }

    @Test func comparisonsLogicListsAndDistinct() {
        let rendered = TodoModel.query()
            .filter(TodoModel.title != "Done" || !TodoModel.isComplete)
            .filter(TodoModel.id < 100 && TodoModel.id >= 1)
            .filter(TodoModel.userID <= 9)
            .filter(TodoModel.userID.notIn([4, 5]))
            .distinct()
            .orderBy(TodoModel.userID.asc, TodoModel.id.desc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT DISTINCT "todos".* FROM "todos" WHERE ("todos"."title" <> $1 OR NOT ("todos"."is_complete")) AND ("todos"."id" < $2 AND "todos"."id" >= $3) AND "todos"."user_id" <= $4 AND "todos"."user_id" NOT IN ($5, $6) ORDER BY "todos"."user_id" ASC, "todos"."id" DESC"#
        )
        #expect(rendered.binds.map(\.description) == ["Done", "100", "1", "9", "4", "5"])

        // An empty list matches nothing for `in` and everything for `notIn`.
        let empty = TodoModel.query().filter(TodoModel.id.in([])).filter(TodoModel.id.notIn([])).render()
        #expect(empty.sql == #"SELECT "todos".* FROM "todos" WHERE FALSE AND TRUE"#)
        #expect(empty.binds.isEmpty)
    }

    @Test func correlatedExistsAndDynamicConditions() {
        var condition = Condition.any
        condition.add(UserModel.region == "us")
        condition.add(UserModel.region.isNull && UserModel.name == "Sam")
        // Waits for slice 21: the empty `Condition.all` filters a `ProjectModel` query with a correlated `whereExists`.
        #expect(UserModel.query().filter(Condition.all).render().sql == #"SELECT "users".* FROM "users""#)
        let rendered = UserModel.query().filter(condition).render()
        #expect(
            rendered.sql
                == #"SELECT "users".* FROM "users" WHERE ("users"."region" = $1 OR ("users"."region" IS NULL AND "users"."name" = $2))"#
        )
        #expect(rendered.binds.map(\.description) == ["us", "Sam"])
    }

    /// `TodoModel` stands in for the kit's `TaskModel`, whose enum columns arrive in slice 26.
    @Test func rowValuesEnumsAndColumnComparisons() {
        let rendered = TodoModel.query()
            .filter(TodoModel.note.isDistinct(from: TodoModel.title))
            .render()
        #expect(rendered.sql == #"SELECT "todos".* FROM "todos" WHERE "todos"."note" IS DISTINCT FROM "todos"."title""#)
        #expect(rendered.binds.isEmpty)
        // Waits for slice 26: `SQL.row(TaskModel.state, TaskModel.title).in([(.pendingReview, "alpha"), (.completed, "beta")])`,
        // `TaskModel.state.in([.inProgress])` and `TaskModel.previousState.isDistinct(from: TaskModel.state)`.

        let arithmetic = TaskModel.query().filter(TaskModel.attempts + 1 < TaskModel.attempts * 2).render()
        #expect(arithmetic.sql == #"SELECT "tasks".* FROM "tasks" WHERE ("tasks"."attempts" + $1) < ("tasks"."attempts" * $2)"#)
        #expect(arithmetic.binds.map(\.description) == ["1", "2"])
    }

    /// The NULL-safe comparisons are never NULL, on either nullability and against values, `nil` and columns.
    @Test func distinctChecksTakeValuesNilAndColumns() {
        let changed: Expr<Bool> = TodoModel.note.isDistinct(from: "today")
        let missing: Expr<Bool> = TodoModel.note.isNotDistinct(from: nil)
        let renamed: Expr<Bool> = TodoModel.title.isDistinct(from: "Ship it")
        let kept: Expr<Bool> = TodoModel.title.isNotDistinct(from: "Ship it")
        let noteIsTitle: Expr<Bool> = TodoModel.title.isNotDistinct(from: TodoModel.note)
        let rendered = TodoModel.query().filter(changed).filter(missing).filter(renamed).filter(kept).filter(noteIsTitle).render()
        #expect(
            rendered.sql
                == #"SELECT "todos".* FROM "todos" WHERE "todos"."note" IS DISTINCT FROM $1 AND "todos"."note" IS NOT DISTINCT FROM NULL AND "todos"."title" IS DISTINCT FROM $2 AND "todos"."title" IS NOT DISTINCT FROM $3 AND "todos"."title" IS NOT DISTINCT FROM "todos"."note""#
        )
        #expect(rendered.binds.map(\.description) == ["today", "Ship it", "Ship it"])
    }

    /// PostgreSQL rejects `a = b > c`, since its comparison operators don't chain, so a comparison inside another
    /// comparison is parenthesized, as rust-dbkit parenthesizes every nested binary expression.
    @Test func nestedComparisonsAreParenthesized() {
        let rendered = TodoModel.query()
            .filter(TodoModel.isComplete == (TodoModel.id > 0))
            .filter((TodoModel.userID <= 9) != TodoModel.isComplete)
            .filter(TodoModel.isComplete.isDistinct(from: TodoModel.title == "Done"))
            .render()
        #expect(
            rendered.sql
                == #"SELECT "todos".* FROM "todos" WHERE "todos"."is_complete" = ("todos"."id" > $1) AND ("todos"."user_id" <= $2) <> "todos"."is_complete" AND "todos"."is_complete" IS DISTINCT FROM ("todos"."title" = $3)"#
        )
        #expect(rendered.binds.map(\.description) == ["0", "9", "Done"])
    }

    /// Arithmetic on integers, floats and `Decimal` with a value on either side, casts keeping nullability, `between`
    /// with expressions as bounds, and arithmetic assigned by `update()`.
    @Test func arithmeticCastsBetweenExpressionsAndAssignments() {
        let perUnit: Expr<Double> = PriceModel.quantity.cast(to: Double.self) / PriceModel.rate
        let minimum: Expr<Double?> = PriceModel.minimum.cast(to: Double.self)
        let remaining: Expr<Decimal?> = 100 - PriceModel.discount
        let withinMinimum: Expr<Bool?> = PriceModel.quantity.between(PriceModel.minimum, PriceModel.quantity + 10)
        let nearRate: Expr<Bool> = PriceModel.rate.between(PriceModel.rate - 1, PriceModel.rate * 2)
        let rendered = PriceModel.query()
            .filter(PriceModel.quantity / 3 > 1)
            .filter(perUnit < minimum)
            .filter(remaining >= PriceModel.amount)
            .filter(withinMinimum)
            .filter(nearRate)
            .orderBy((PriceModel.amount * PriceModel.quantity.cast(to: Decimal.self)).desc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "prices".* FROM "prices" WHERE ("prices"."quantity" / $1) > $2 AND (CAST("prices"."quantity" AS double precision) / "prices"."rate") < CAST("prices"."minimum" AS double precision) AND ($3 - "prices"."discount") >= "prices"."amount" AND "prices"."quantity" BETWEEN "prices"."minimum" AND ("prices"."quantity" + $4) AND "prices"."rate" BETWEEN ("prices"."rate" - $5) AND ("prices"."rate" * $6) ORDER BY ("prices"."amount" * CAST("prices"."quantity" AS numeric)) DESC"#
        )
        #expect(rendered.binds.map(\.description) == ["3", "1", "100", "10", "1.0", "2.0"])

        let update = PriceModel.update()
            .set(PriceModel.quantity, to: PriceModel.quantity - 1)
            .set(PriceModel.minimum, to: PriceModel.quantity / 2)
            .set(PriceModel.discount, to: PriceModel.discount * 2)
            .filter(PriceModel.id == 7)
            .render()
        #expect(
            update.sql
                == #"UPDATE "prices" SET "quantity" = ("prices"."quantity" - $1), "minimum" = ("prices"."quantity" / $2), "discount" = ("prices"."discount" * $3) WHERE "prices"."id" = $4"#
        )
        #expect(update.binds.map(\.description) == ["1", "2", "2", "7"])
    }

    /// `Interval` keeps PostgreSQL's three components. Intervals add to and subtract from each other and timestamps,
    /// keeping nullability, and cast to and from text.
    @Test func intervalComponentsArithmeticAndCasts() {
        #expect(Interval.days(2) == Interval(days: 2))
        #expect(Interval.hours(2) == Interval(microseconds: 7_200_000_000))
        #expect(Interval.minutes(-30) == Interval(microseconds: -1_800_000_000))
        #expect(Interval.seconds(90) == Interval(microseconds: 90_000_000))
        let mixed = Interval(months: 1, days: 2, microseconds: 3)
        #expect(mixed.months == 1 && mixed.days == 2 && mixed.microseconds == 3)
        #expect(mixed.description == "1 mons 2 days 3 us")

        let extended: Expr<Interval?> = LeaseModel.term + LeaseModel.grace
        let shortened: Expr<Interval> = LeaseModel.term - Interval.minutes(15)
        let ends: Expr<Date> = LeaseModel.startsAt + LeaseModel.term
        let lastHour: Expr<Date?> = LeaseModel.endsAt - Interval.hours(1)
        let noted: Expr<Interval> = LeaseModel.note.cast(to: Interval.self)
        let termText: Expr<String> = LeaseModel.term.cast(to: String.self)
        let rendered = LeaseModel.query()
            .filter(extended > Interval.days(1))
            .filter(lastHour >= ends)
            .filter(noted == shortened)
            .orderBy(termText.asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "leases".* FROM "leases" WHERE ("leases"."term" + "leases"."grace") > $1 AND ("leases"."ends_at" - $2) >= ("leases"."starts_at" + "leases"."term") AND CAST("leases"."note" AS interval) = ("leases"."term" - $3) ORDER BY CAST("leases"."term" AS text) ASC"#
        )
        #expect(rendered.binds.map(\.description) == ["0 mons 1 days 0 us", "0 mons 0 days 3600000000 us", "0 mons 0 days 900000000 us"])

        // Unlike rust-dbkit, whole units such as hours take fractions too.
        let fractional = LeaseModel.query().orderBy(SQL.interval(hours: 1.5).asc).render()
        #expect(fractional.sql == #"SELECT "leases".* FROM "leases" ORDER BY ($1 * INTERVAL '1 hour') ASC"#)
        #expect(fractional.binds.map(\.description) == ["1.5"])
    }

    @Test func aggregatesProjectionsAndFunctions() {
        let usSale = SaleModel.region == "us"
        let rendered = SaleModel.query()
            .select(
                SaleModel.region.as("region"),
                SQL.count(SaleModel.id).filter(usSale).as("us_sale_count"),
                SQL.sum(SaleModel.amount).as("total")
            )
            .groupBy(SaleModel.region)
            .having(SQL.sum(SaleModel.amount) > 0)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "sales"."region" AS "region", COUNT("sales"."id") FILTER (WHERE "sales"."region" = $1) AS "us_sale_count", SUM("sales"."amount") AS "total" FROM "sales" GROUP BY "sales"."region" HAVING SUM("sales"."amount") > $2"#
        )

        let buckets = SaleModel.query()
            .select(
                SQL.dateTrunc(.day, SaleModel.createdAt).as("bucket"),
                SQL.count(SaleModel.id).filter(usSale).as("us_sale_count"),
                SQL.sum(SaleModel.amount).as("total")
            )
            .groupBy(SQL.dateTrunc(.day, SaleModel.createdAt))
            .having(SQL.sum(SaleModel.amount) > 0)
            .render()
        #expect(
            buckets.sql
                == #"SELECT DATE_TRUNC('day', "sales"."created_at") AS "bucket", COUNT("sales"."id") FILTER (WHERE "sales"."region" = $1) AS "us_sale_count", SUM("sales"."amount") AS "total" FROM "sales" GROUP BY DATE_TRUNC('day', "sales"."created_at") HAVING SUM("sales"."amount") > $2"#
        )
    }

    /// Every `DateTruncUnit` renders PostgreSQL's name for it. Functions work in `update().set`, `GROUP BY` and
    /// `HAVING`, and inside and around aggregates.
    @Test func sqlFunctionsInEveryClause() {
        let units: [(DateTruncUnit, String)] = [
            (.microseconds, "microseconds"), (.milliseconds, "milliseconds"), (.second, "second"), (.minute, "minute"),
            (.hour, "hour"), (.day, "day"), (.week, "week"), (.month, "month"), (.quarter, "quarter"), (.year, "year"),
            (.decade, "decade"), (.century, "century"), (.millennium, "millennium"),
        ]
        for (unit, name) in units {
            let rendered = LeaseModel.query().filter(SQL.dateTrunc(unit, LeaseModel.startsAt) < SQL.now()).render()
            #expect(rendered.sql == #"SELECT "leases".* FROM "leases" WHERE DATE_TRUNC('\#(name)', "leases"."starts_at") < NOW()"#)
        }

        let update = UserModel.update()
            .set(UserModel.name, to: UserModel.name.uppercased())
            .set(UserModel.region, to: UserModel.region.trimmed())
            .filter(UserModel.email.lowercased().hasPrefix("admin"))
            .render()
        #expect(
            update.sql
                == #"UPDATE "users" SET "name" = UPPER("users"."name"), "region" = TRIM("users"."region") WHERE STARTS_WITH(LOWER("users"."email"), $1)"#
        )
        #expect(update.binds.map(\.description) == ["admin"])

        let grouped: Projection<String, String?, String> = SaleModel.query()
            .select(
                SaleModel.region.lowercased().as("region"),
                SQL.max(SaleModel.region.uppercased()).as("label"),
                (SQL.min(SaleModel.region).trimmed() ?? "").as("first_region")
            )
            .groupBy(SaleModel.region.lowercased())
            .having(SQL.greatest(SQL.sum(SaleModel.amount), 0) > 100)
            .orderBy(SQL.least(SQL.countAll(), 10).desc)
        let rendered = grouped.render()
        #expect(
            rendered.sql
                == #"SELECT LOWER("sales"."region") AS "region", MAX(UPPER("sales"."region")) AS "label", COALESCE(TRIM(MIN("sales"."region")), $1) AS "first_region" FROM "sales" GROUP BY LOWER("sales"."region") HAVING GREATEST(SUM("sales"."amount"), $2) > $3 ORDER BY LEAST(COUNT(*), $4) DESC"#
        )
        #expect(rendered.binds.map(\.description) == ["", "0", "100", "10"])
    }

    /// Text functions work in `update().set`, `GROUP BY` and `HAVING`, take aggregates, and nest in the other functions.
    @Test func textFunctionsInEveryClause() {
        let update = UserModel.update()
            .set(UserModel.name, to: SQL.concatWithSeparator(" ", SQL.titleCase(UserModel.name), SQL.left(UserModel.email, 3)))
            .set(UserModel.region, to: SQL.trimEndChars(UserModel.region, "!"))
            .filter(SQL.position(UserModel.email, "@") > 1)
            .render()
        #expect(
            update.sql
                == #"UPDATE "users" SET "name" = CONCAT_WS($1, INITCAP("users"."name"), LEFT("users"."email", $2)), "region" = TRIM(TRAILING $3 FROM "users"."region") WHERE STRPOS("users"."email", $4) > $5"#
        )
        #expect(update.binds.map(\.description) == [" ", "3", "!", "@", "1"])

        let grouped: Projection<String, String, Int32> = SaleModel.query()
            .select(
                SQL.splitPart(SQL.reverse(SaleModel.region), "-", 1).as("suffix"),
                SQL.concat(SQL.min(SaleModel.region), ":", SQL.max(SaleModel.region)).as("span"),
                SQL.greatest(SQL.charLength(SQL.max(SaleModel.region)), 0).as("longest")
            )
            .groupBy(SQL.reverse(SaleModel.region))
            .having(SQL.reverse(SQL.max(SaleModel.region)).hasPrefix("su"))
            .orderBy(SQL.padStart(SQL.min(SaleModel.region) ?? "", 8, "0").uppercased().asc)
        let rendered = grouped.render()
        #expect(
            rendered.sql
                == #"SELECT SPLIT_PART(REVERSE("sales"."region"), $1, $2) AS "suffix", CONCAT(MIN("sales"."region"), $3, MAX("sales"."region")) AS "span", GREATEST(CHAR_LENGTH(MAX("sales"."region")), $4) AS "longest" FROM "sales" GROUP BY REVERSE("sales"."region") HAVING STARTS_WITH(REVERSE(MAX("sales"."region")), $5) ORDER BY UPPER(LPAD(COALESCE(MIN("sales"."region"), $6), $7, $8)) ASC"#
        )
        #expect(rendered.binds.map(\.description) == ["-", "1", ":", "0", "su", "", "8", "0"])
    }

    /// Regex and Unicode functions work in `update().set`, `GROUP BY` and `HAVING`, take aggregates, and nest in the
    /// other functions. Captures compare with a `RegexCaptures` value, which binds as a text array.
    @Test func regexAndUnicodeFunctionsInEveryClause() {
        let update = UserModel.update()
            .set(UserModel.name, to: SQL.normalize(SQL.regexReplace(UserModel.name, #"\s+"#, " ", .global), .nfkc))
            .set(UserModel.region, to: SQL.coalesce(SQL.regexExtract(UserModel.email, "@(.+)$"), SQL.caseFold(UserModel.region)))
            .filter(SQL.regexIsMatch(UserModel.email, "^[a-z]") && SQL.firstCodepoint(UserModel.name) > 64)
            .render()
        #expect(
            update.sql
                == #"UPDATE "users" SET "name" = NORMALIZE(REGEXP_REPLACE("users"."name", $1, $2, $3), NFKC), "region" = COALESCE(REGEXP_SUBSTR("users"."email", $4), CASEFOLD("users"."region")) WHERE (REGEXP_LIKE("users"."email", $5) AND ASCII("users"."name") > $6)"#
        )
        #expect(update.binds.map(\.description) == [#"\s+"#, " ", "g", "@(.+)$", "^[a-z]", "64"])

        let grouped: Projection<[String], Int32, String?> = SaleModel.query()
            .select(
                SQL.regexSplit(SQL.toASCII(SaleModel.region), "-", .caseInsensitive).as("parts"),
                SQL.greatest(SQL.regexCount(SQL.max(SaleModel.region), "u"), 0).as("most_matches"),
                SQL.fromCodepoint(SQL.regexPosition(SQL.min(SaleModel.region), "s") + 64).as("marker")
            )
            .groupBy(SQL.regexSplit(SQL.toASCII(SaleModel.region), "-", .caseInsensitive))
            .having(SQL.isUnicodeAssigned(SQL.max(SaleModel.region)))
            .orderBy(SQL.regexCaptures(SQL.min(SaleModel.region), "(u)(x)?").desc)
            .filter(SQL.regexCaptures(SaleModel.region, "(u)(x)?") == RegexCaptures(["u", nil]))
        let rendered = grouped.render()
        #expect(
            rendered.sql
                == #"SELECT REGEXP_SPLIT_TO_ARRAY(TO_ASCII("sales"."region"), $1, $2) AS "parts", GREATEST(REGEXP_COUNT(MAX("sales"."region"), $3), $4) AS "most_matches", CHR((REGEXP_INSTR(MIN("sales"."region"), $5) + $6)) AS "marker" FROM "sales" WHERE REGEXP_MATCH("sales"."region", $7) = $8 GROUP BY REGEXP_SPLIT_TO_ARRAY(TO_ASCII("sales"."region"), $9, $10) HAVING UNICODE_ASSIGNED(MAX("sales"."region")) ORDER BY REGEXP_MATCH(MIN("sales"."region"), $11) DESC"#
        )
        #expect(rendered.binds[7].value as? RegexCaptures == RegexCaptures(["u", nil]))
        #expect(RegexCaptures(["u", nil]).groups == ["u", nil])
    }

    /// `groupBy` takes several expressions, `having` predicates combine with `AND`, and aggregates take computed values.
    /// `SQL.countAll()` counts rows.
    @Test func groupingByExpressionsAndAggregatingComputedValues() {
        let bucket: Expr<Int32> = PriceModel.quantity / 10
        let doubled: AggregateExpr<Int64?> = SQL.sum(PriceModel.quantity * 2)
        let query: Projection<Int32, Double, Int64, Int64?, Decimal?> = PriceModel.query()
            .select(
                bucket.as("bucket"),
                PriceModel.rate.as("rate"),
                SQL.countAll().as("price_count"),
                doubled.as("doubled_quantity"),
                SQL.max(PriceModel.discount ?? 0).as("largest_discount")
            )
            .groupBy(bucket, PriceModel.rate)
            .having(SQL.countAll() > 1)
            .having(SQL.sum(PriceModel.amount) > 100)
            .orderBy(doubled.desc)
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT ("prices"."quantity" / $1) AS "bucket", "prices"."rate" AS "rate", COUNT(*) AS "price_count", SUM(("prices"."quantity" * $2)) AS "doubled_quantity", MAX(COALESCE("prices"."discount", $3)) AS "largest_discount" FROM "prices" GROUP BY ("prices"."quantity" / $4), "prices"."rate" HAVING COUNT(*) > $5 AND SUM("prices"."amount") > $6 ORDER BY SUM(("prices"."quantity" * $7)) DESC"#
        )
        #expect(rendered.binds.map(\.description) == ["10", "2", "0", "10", "1", "100", "2"])
    }

    /// `SUM` of intervals is an interval, NULL without rows. Aggregates take interval arithmetic and shift timestamps.
    @Test func aggregatesOfIntervalsAndTimestamps() {
        let totalTerm: AggregateExpr<Interval?> = SQL.sum(LeaseModel.term + LeaseModel.grace)
        let latestEnd: AggregateExpr<Date?> = SQL.max(LeaseModel.startsAt + LeaseModel.term)
        let backToBackEnd: Expr<Date?> = SQL.min(LeaseModel.startsAt) + SQL.sum(LeaseModel.term)
        let query: Projection<Interval?, Date?, Date?> = LeaseModel.query()
            .select(totalTerm.as("total_term"), latestEnd.as("latest_end"), backToBackEnd.as("back_to_back_end"))
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT SUM(("leases"."term" + "leases"."grace")) AS "total_term", MAX(("leases"."starts_at" + "leases"."term")) AS "latest_end", (MIN("leases"."starts_at") + SUM("leases"."term")) AS "back_to_back_end" FROM "leases""#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func mutations() {
        let insert = UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com"))
            .returningAll()
            .render()
        #expect(insert.sql == #"INSERT INTO "users" ("name", "email", "region") VALUES ($1, $2, NULL) RETURNING *"#)
        let upsert = UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com"))
            .onConflict(UserModel.email, doUpdate: UserModel.name, UserModel.region)
            .returningAll()
            .render()
        #expect(
            upsert.sql
                == #"INSERT INTO "users" ("name", "email", "region") VALUES ($1, $2, NULL) ON CONFLICT ("email") DO UPDATE SET "name" = EXCLUDED."name", "region" = EXCLUDED."region" RETURNING *"#
        )
        // Column lists kept in constants render the same upsert.
        let updates = (UserModel.name, UserModel.region)
        let stored = UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com"))
            .onConflict(UserModel.email, doUpdate: updates)
            .returningAll()
            .render()
        #expect(stored.sql == upsert.sql)
        let update = TaskModel.update()
            .set(TaskModel.attempts, to: TaskModel.attempts + 1)
            .filter(TaskModel.id == 42)
            .render()
        #expect(update.sql == #"UPDATE "tasks" SET "attempts" = ("tasks"."attempts" + $1) WHERE "tasks"."id" = $2"#)
        #expect(update.binds.map(\.description) == ["1", "42"])
        // Waits for slice 26: the same update also setting the enum `state` to `.completed` and `previousState` to `nil`.
        // Waits for slice 21: `TaskModel.delete().whereExists(…)` with a correlated `ProjectModel` subquery.
    }

    /// A condition nests in another through its predicate, which updates and deletes filter by once unwrapped. A row
    /// value matches composite keys and takes `nil` for a nullable column.
    @Test func nestedConditionsAndRowValuesOnKeys() throws {
        var condition = Condition.all
        #expect(condition.isEmpty)
        #expect(condition.predicate == nil)

        var owners = Condition.any
        owners.add(TodoModel.userID == 1)
        owners.add(TodoModel.userID == 2)
        condition.add(TodoModel.note == "today")
        condition.add(try #require(owners.predicate))
        #expect(!condition.isEmpty)
        let predicate: Expr<Bool?> = try #require(condition.predicate)
        let update = TodoModel.update().set(TodoModel.isComplete, to: true).filter(predicate).render()
        #expect(
            update.sql
                == #"UPDATE "todos" SET "is_complete" = $1 WHERE ("todos"."note" = $2 AND ("todos"."user_id" = $3 OR "todos"."user_id" = $4))"#
        )
        #expect(update.binds.map(\.description) == ["true", "today", "1", "2"])
        let delete = TodoModel.delete().filter(predicate).render()
        #expect(delete.sql == #"DELETE FROM "todos" WHERE ("todos"."note" = $1 AND ("todos"."user_id" = $2 OR "todos"."user_id" = $3))"#)
        #expect(delete.binds.map(\.description) == ["today", "1", "2"])

        let lines: Expr<Bool> = SQL.row(OrderLineModel.orderID, OrderLineModel.lineID).in([(7, 8), (7, 9)])
        let deletedLines = OrderLineModel.delete().filter(lines).render()
        #expect(
            deletedLines.sql
                == #"DELETE FROM "order_lines" WHERE ("order_lines"."order_id", "order_lines"."line_id") IN (($1, $2), ($3, $4))"#)
        #expect(deletedLines.binds.map(\.description) == ["7", "8", "7", "9"])

        let notes: Expr<Bool?> = SQL.row(TodoModel.id, TodoModel.note).in([(1, "today"), (2, nil)])
        let todos = TodoModel.query().filter(notes).render()
        #expect(todos.sql == #"SELECT "todos".* FROM "todos" WHERE ("todos"."id", "todos"."note") IN (($1, $2), ($3, NULL))"#)
        #expect(todos.binds.map(\.description) == ["1", "today", "2"])
    }

    @Test func conflictClausesWithoutTargetAndWithBothColumnListsInConstants() {
        let ignored = UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com")).onConflictDoNothing().render()
        #expect(ignored.sql == #"INSERT INTO "users" ("name", "email", "region") VALUES ($1, $2, NULL) ON CONFLICT DO NOTHING"#)
        #expect(ignored.binds.map(\.description) == ["Alex", "a@b.com"])

        let line = OrderLineModel.Insert(orderID: 7, lineID: 8, note: "Updated via upsert")
        let target = (OrderLineModel.orderID, OrderLineModel.lineID)
        let updates = (OrderLineModel.note, OrderLineModel.lineID)
        let stored = OrderLineModel.insert(line).onConflict(target, doUpdate: updates).render()
        #expect(
            stored.sql
                == #"INSERT INTO "order_lines" ("order_id", "line_id", "note") VALUES ($1, $2, $3) ON CONFLICT ("order_id", "line_id") DO UPDATE SET "note" = EXCLUDED."note", "line_id" = EXCLUDED."line_id""#
        )
        #expect(stored.binds.map(\.description) == ["7", "8", "Updated via upsert"])
        let listed = OrderLineModel.insert(line)
            .onConflict(OrderLineModel.orderID, OrderLineModel.lineID, doUpdate: OrderLineModel.note, OrderLineModel.lineID)
            .render()
        #expect(listed.sql == stored.sql)
    }

    @Test func insertDefaultsAndMutationsWithoutReturning() {
        // `note` defaults to `nil` and `isComplete` to its Swift default; the auto-increment `id` is left out.
        let defaults = TodoModel.insert(TodoModel.Insert(userID: 2, title: "Ship it")).render()
        #expect(defaults.sql == #"INSERT INTO "todos" ("user_id", "title", "note", "is_complete") VALUES ($1, $2, NULL, $3)"#)
        #expect(defaults.binds.map(\.description) == ["2", "Ship it", "false"])
        let explicit = TodoModel.insert(TodoModel.Insert(userID: 2, title: "Ship it", note: "today", isComplete: true)).render()
        #expect(explicit.sql == #"INSERT INTO "todos" ("user_id", "title", "note", "is_complete") VALUES ($1, $2, $3, $4)"#)
        #expect(explicit.binds.map(\.description) == ["2", "Ship it", "today", "true"])

        #expect(TodoModel.delete().render().sql == #"DELETE FROM "todos""#)
        let deleted = TodoModel.delete().filter(TodoModel.userID == 2).returningAll().render()
        #expect(deleted.sql == #"DELETE FROM "todos" WHERE "todos"."user_id" = $1 RETURNING *"#)
        #expect(deleted.binds.map(\.description) == ["2"])
    }
}
