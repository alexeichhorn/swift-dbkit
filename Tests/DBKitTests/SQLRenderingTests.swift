import DBKit
import Testing

@Suite struct SQLRenderingTests {
    @Test func filtersAndOrdering() {
        let userID: Int64 = 7
        // Waits for slice 8: the kit's `filtersOrderingAndNullHandling`, which adds `TodoModel.note == nil` and an optional `String?` value to these filters.
        let rendered = TodoModel.query()
            .filter(TodoModel.userID == userID)
            .filter(TodoModel.title.ilike("%milk%"))
            .orderBy(TodoModel.id.desc)
            .limit(20)
            .offset(40)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "todos".* FROM "todos" WHERE "todos"."user_id" = $1 AND "todos"."title" ILIKE $2 ORDER BY "todos"."id" DESC LIMIT 20 OFFSET 40"#
        )
        #expect(rendered.binds.map(\.description) == ["7", "%milk%"])
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

    @Test func mutations() {
        let insert = UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com"))
            .returningAll()
            .render()
        #expect(insert.sql == #"INSERT INTO "users" ("name", "email", "region") VALUES ($1, $2, NULL) RETURNING *"#)
        // Waits for slice 6: `.onConflict(UserModel.email, doUpdate: UserModel.name, UserModel.region)` on this insert,
        // rendering `ON CONFLICT ("email") DO UPDATE SET "name" = EXCLUDED."name", "region" = EXCLUDED."region"` before
        // `RETURNING *`, and the same SQL with the update columns kept in a tuple constant.
        // Waits for slices 8, 10 and 26: `TaskModel.update()` setting an enum `state`, `previousState` to `nil` and
        // `attempts` to `TaskModel.attempts + 1`.
        // Waits for slice 21: `TaskModel.delete().whereExists(…)` with a correlated `ProjectModel` subquery.
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
