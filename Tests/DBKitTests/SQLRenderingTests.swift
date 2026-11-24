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
}
