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
        // Waits for slice 14: `select(TodoModel.note == "today")` decodes as `Bool?`, `nil` for a row whose note is NULL.
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

    /// `TodoModel` stands in for the kit's `TaskModel`, whose enum columns arrive in slice 26.
    @Test func rowValuesEnumsAndColumnComparisons() {
        let rendered = TodoModel.query()
            .filter(TodoModel.note.isDistinct(from: TodoModel.title))
            .render()
        #expect(rendered.sql == #"SELECT "todos".* FROM "todos" WHERE "todos"."note" IS DISTINCT FROM "todos"."title""#)
        #expect(rendered.binds.isEmpty)
        // Waits for slice 13: `SQL.row(TaskModel.state, TaskModel.title).in([(.pendingReview, "alpha"), (.completed, "beta")])`.
        // Waits for slice 26: `TaskModel.state.in([.inProgress])` and `TaskModel.previousState.isDistinct(from: TaskModel.state)`.

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
