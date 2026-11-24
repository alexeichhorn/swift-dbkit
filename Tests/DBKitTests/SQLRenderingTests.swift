import DBKit
import Testing

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
        // Waits for slice 10: `TaskModel.attempts + 1 < TaskModel.attempts * 2`, rendered `("tasks"."attempts" + $6) < ("tasks"."attempts" * $7)`.
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
        // Waits for slices 8, 10 and 26: `TaskModel.update()` setting an enum `state`, `previousState` to `nil` and
        // `attempts` to `TaskModel.attempts + 1`.
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
