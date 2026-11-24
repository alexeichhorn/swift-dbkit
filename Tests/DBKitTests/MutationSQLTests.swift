import DBKit
import Testing

/// The `users` table of rust-dbkit's `mutation_sql.rs` for its inserts that set only `email`.
@Model(table: "users")
class MutationEmailUserModel {
    @Key @AutoIncrement var id: Int64
    var email: String?
}

/// The same `users` table with `name`, for the mutations that use both columns.
@Model(table: "users")
class MutationUserModel {
    @Key @AutoIncrement var id: Int64
    var email: String?
    var name: String
}

@Suite struct MutationSQLTests {
    @Test func compilesInsertReturningAll() {
        let rendered = MutationEmailUserModel.insert(MutationEmailUserModel.Insert(email: "a@b.com")).returningAll().render()
        #expect(rendered.sql == #"INSERT INTO "users" ("email") VALUES ($1) RETURNING *"#)
        #expect(rendered.binds.map(\.description) == ["a@b.com"])
    }

    // Waits for slice 8: `compilesInsertWithNull`, `Insert(email: nil)` rendering `VALUES (NULL)` without binds.

    @Test func compilesInsertWithSomeForNullableColumn() {
        let email: String? = "a@b.com"
        let rendered = MutationEmailUserModel.insert(MutationEmailUserModel.Insert(email: email)).returningAll().render()
        #expect(rendered.sql == #"INSERT INTO "users" ("email") VALUES ($1) RETURNING *"#)
        #expect(rendered.binds.map(\.description) == ["a@b.com"])
    }

    @Test func compilesInsertManyRows() {
        let rendered = MutationUserModel.insert([
            MutationUserModel.Insert(email: "a@b.com", name: "Alice"),
            MutationUserModel.Insert(email: nil, name: "Bob"),
        ])
        .returningAll()
        .render()
        #expect(rendered.sql == #"INSERT INTO "users" ("email", "name") VALUES ($1, $2), (NULL, $3) RETURNING *"#)
        #expect(rendered.binds.map(\.description) == ["a@b.com", "Alice", "Bob"])
    }

    // Waits for slice 6: `compilesInsertOnConflictDoNothingWithSingleTarget`,
    // `compilesInsertManyOnConflictDoNothingWithCompositeTarget`,
    // `compilesInsertOnConflictDoUpdateWithCompositeTargetAndSelectedOverwriteColumns`,
    // `compilesInsertOnConflictDoUpdateWithFourSelectedOverwriteColumns` and
    // `compilesInsertOnConflictDoUpdateWithNullInsertValuesAndPreservesBindOrder`.

    /// rust-dbkit also returns `id` here; `returning(columns)` is left out, see `docs/rust-parity.md`.
    @Test func compilesUpdateWithFilter() {
        let rendered = MutationUserModel.update()
            .set(MutationUserModel.email, to: "new@b.com")
            .filter(MutationUserModel.id == 1)
            .render()
        #expect(rendered.sql == #"UPDATE "users" SET "email" = $1 WHERE "users"."id" = $2"#)
        #expect(rendered.binds.map(\.description) == ["new@b.com", "1"])
    }

    @Test func compilesUpdateReturningAllSingleField() {
        let rendered = MutationUserModel.update()
            .set(MutationUserModel.name, to: "Updated")
            .filter(MutationUserModel.id == 1)
            .returningAll()
            .render()
        #expect(rendered.sql == #"UPDATE "users" SET "name" = $1 WHERE "users"."id" = $2 RETURNING *"#)
        #expect(rendered.binds.map(\.description) == ["Updated", "1"])
    }

    @Test func compilesUpdateWithCompositeKeyFilters() {
        let rendered = OrderLineModel.update()
            .set(OrderLineModel.note, to: "Updated")
            .filter(OrderLineModel.orderID == 1)
            .filter(OrderLineModel.lineID == 2)
            .returningAll()
            .render()
        #expect(
            rendered.sql
                == #"UPDATE "order_lines" SET "note" = $1 WHERE "order_lines"."order_id" = $2 AND "order_lines"."line_id" = $3 RETURNING *"#
        )
        #expect(rendered.binds.map(\.description) == ["Updated", "1", "2"])
    }

    // Waits for slice 8: `compilesUpdateSetNull`, `.set(email, to: nil)` rendering `SET "email" = NULL`.

    @Test func compilesUpdateSetSomeForNullableColumn() {
        let email: String? = "new@b.com"
        let rendered = MutationUserModel.update()
            .set(MutationUserModel.email, to: email)
            .filter(MutationUserModel.id == 1)
            .returningAll()
            .render()
        #expect(rendered.sql == #"UPDATE "users" SET "email" = $1 WHERE "users"."id" = $2 RETURNING *"#)
        #expect(rendered.binds.map(\.description) == ["new@b.com", "1"])
    }

    // Waits for slice 21: `compilesUpdateWhereExistsWithCorrelatedSubqueryAndReturningAll` and
    // `compilesUpdateWhereNotExistsWithCorrelatedSubquery`.

    @Test func compilesDeleteWithFilter() {
        let rendered = MutationUserModel.delete().filter(MutationUserModel.id == 42).render()
        #expect(rendered.sql == #"DELETE FROM "users" WHERE "users"."id" = $1"#)
        #expect(rendered.binds.map(\.description) == ["42"])
    }

    // Waits for slice 21: `compilesDeleteWhereExistsWithCorrelatedSubqueryAndReturningAll` and
    // `compilesDeleteWhereNotExistsWithCorrelatedSubquery`.
}
