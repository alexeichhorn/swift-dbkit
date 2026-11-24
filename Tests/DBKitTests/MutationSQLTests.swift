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

/// rust-dbkit's `teams` of `mutation_sql.rs`, named apart from the `TeamModel` of the integration tests.
@Model(table: "teams")
class MutationTeamModel {
    @Key var id: Int64
    var ownerID: Int64
    var state: String
}

@Model(table: "team_members")
class MutationTeamMemberModel {
    @Key var id: Int64
    var teamID: Int64
    var role: String
}

@Suite struct MutationSQLTests {
    @Test func compilesInsertReturningAll() {
        let rendered = MutationEmailUserModel.insert(MutationEmailUserModel.Insert(email: "a@b.com")).returningAll().render()
        #expect(rendered.sql == #"INSERT INTO "users" ("email") VALUES ($1) RETURNING *"#)
        #expect(rendered.binds.map(\.description) == ["a@b.com"])
    }

    @Test func compilesInsertWithNull() {
        let rendered = MutationEmailUserModel.insert(MutationEmailUserModel.Insert(email: nil)).returningAll().render()
        #expect(rendered.sql == #"INSERT INTO "users" ("email") VALUES (NULL) RETURNING *"#)
        #expect(rendered.binds.isEmpty)
    }

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

    @Test func compilesInsertOnConflictDoNothingWithSingleTarget() {
        let rendered = MutationUserModel.insert(MutationUserModel.Insert(email: "a@b.com", name: "Alice"))
            .onConflictDoNothing(MutationUserModel.email)
            .returningAll()
            .render()
        #expect(rendered.sql == #"INSERT INTO "users" ("email", "name") VALUES ($1, $2) ON CONFLICT ("email") DO NOTHING RETURNING *"#)
        #expect(rendered.binds.map(\.description) == ["a@b.com", "Alice"])
    }

    @Test func compilesInsertManyOnConflictDoNothingWithCompositeTarget() {
        let rendered = RunPayloadModel.insert([
            RunPayloadModel.Insert(targetID: 10, runID: 20, payload: "v1", source: "seed", version: 1),
            RunPayloadModel.Insert(targetID: 11, runID: 21, payload: "v2", source: "seed-2", version: 2),
        ])
        .onConflictDoNothing(RunPayloadModel.targetID, RunPayloadModel.runID)
        .returningAll()
        .render()
        #expect(
            rendered.sql
                == #"INSERT INTO "run_payloads" ("target_id", "run_id", "payload", "source", "version") VALUES ($1, $2, $3, $4, $5), ($6, $7, $8, $9, $10) ON CONFLICT ("target_id", "run_id") DO NOTHING RETURNING *"#
        )
        #expect(rendered.binds.map(\.description) == ["10", "20", "v1", "seed", "1", "11", "21", "v2", "seed-2", "2"])
    }

    @Test func compilesInsertOnConflictDoUpdateWithCompositeTargetAndSelectedOverwriteColumns() {
        let rendered = RunPayloadModel.insert(
            RunPayloadModel.Insert(targetID: 42, runID: 7, payload: "new-payload", source: "new-source", version: 3)
        )
        .onConflict(RunPayloadModel.targetID, RunPayloadModel.runID, doUpdate: RunPayloadModel.payload, RunPayloadModel.version)
        .returningAll()
        .render()
        #expect(
            rendered.sql
                == #"INSERT INTO "run_payloads" ("target_id", "run_id", "payload", "source", "version") VALUES ($1, $2, $3, $4, $5) ON CONFLICT ("target_id", "run_id") DO UPDATE SET "payload" = EXCLUDED."payload", "version" = EXCLUDED."version" RETURNING *"#
        )
        #expect(rendered.binds.map(\.description) == ["42", "7", "new-payload", "new-source", "3"])
    }

    @Test func compilesInsertOnConflictDoUpdateWithFourSelectedOverwriteColumns() {
        let rendered = RunPayloadModel.insert(
            RunPayloadModel.Insert(targetID: 42, runID: 7, payload: "new-payload", source: "new-source", version: 3)
        )
        .onConflict(
            RunPayloadModel.targetID, RunPayloadModel.runID,
            doUpdate: RunPayloadModel.payload, RunPayloadModel.source, RunPayloadModel.version, RunPayloadModel.runID
        )
        .returningAll()
        .render()
        #expect(
            rendered.sql
                == #"INSERT INTO "run_payloads" ("target_id", "run_id", "payload", "source", "version") VALUES ($1, $2, $3, $4, $5) ON CONFLICT ("target_id", "run_id") DO UPDATE SET "payload" = EXCLUDED."payload", "source" = EXCLUDED."source", "version" = EXCLUDED."version", "run_id" = EXCLUDED."run_id" RETURNING *"#
        )
        #expect(rendered.binds.map(\.description) == ["42", "7", "new-payload", "new-source", "3"])
    }

    @Test func compilesInsertOnConflictDoUpdateWithNullInsertValuesAndPreservesBindOrder() {
        let rendered = MutationUserModel.insert(MutationUserModel.Insert(email: nil, name: "fallback-name"))
            .onConflict(MutationUserModel.email, doUpdate: MutationUserModel.name)
            .returningAll()
            .render()
        #expect(
            rendered.sql
                == #"INSERT INTO "users" ("email", "name") VALUES (NULL, $1) ON CONFLICT ("email") DO UPDATE SET "name" = EXCLUDED."name" RETURNING *"#
        )
        #expect(rendered.binds.map(\.description) == ["fallback-name"])
    }

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

    @Test func compilesUpdateSetNull() {
        let rendered = MutationUserModel.update()
            .set(MutationUserModel.email, to: nil)
            .filter(MutationUserModel.id == 1)
            .returningAll()
            .render()
        #expect(rendered.sql == #"UPDATE "users" SET "email" = NULL WHERE "users"."id" = $1 RETURNING *"#)
        #expect(rendered.binds.map(\.description) == ["1"])
    }

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

    @Test func compilesUpdateWhereExistsWithCorrelatedSubqueryAndReturningAll() {
        let subquery = MutationTeamModel.query()
            .select(MutationTeamModel.id)
            .filter(MutationTeamModel.id == MutationTeamMemberModel.teamID)
            .filter(MutationTeamModel.ownerID == 7)
            .filter(MutationTeamModel.state == "active")
        let rendered = MutationTeamMemberModel.update()
            .set(MutationTeamMemberModel.role, to: "observer")
            .whereExists(subquery)
            .returningAll()
            .render()
        #expect(
            rendered.sql
                == #"UPDATE "team_members" SET "role" = $1 WHERE EXISTS (SELECT "teams"."id" FROM "teams" WHERE "teams"."id" = "team_members"."team_id" AND "teams"."owner_id" = $2 AND "teams"."state" = $3) RETURNING *"#
        )
        #expect(rendered.binds.map(\.description) == ["observer", "7", "active"])
    }

    @Test func compilesUpdateWhereNotExistsWithCorrelatedSubquery() {
        let subquery = MutationTeamMemberModel.query()
            .select(MutationTeamMemberModel.id)
            .filter(MutationTeamMemberModel.teamID == MutationTeamModel.id)
            .filter(MutationTeamMemberModel.role == "lead")
        let rendered = MutationTeamModel.update()
            .set(MutationTeamModel.state, to: "inactive")
            .whereNotExists(subquery)
            .filter(MutationTeamModel.ownerID == 9)
            .render()
        #expect(
            rendered.sql
                == #"UPDATE "teams" SET "state" = $1 WHERE NOT EXISTS (SELECT "team_members"."id" FROM "team_members" WHERE "team_members"."team_id" = "teams"."id" AND "team_members"."role" = $2) AND "teams"."owner_id" = $3"#
        )
        #expect(rendered.binds.map(\.description) == ["inactive", "lead", "9"])
    }

    @Test func compilesDeleteWithFilter() {
        let rendered = MutationUserModel.delete().filter(MutationUserModel.id == 42).render()
        #expect(rendered.sql == #"DELETE FROM "users" WHERE "users"."id" = $1"#)
        #expect(rendered.binds.map(\.description) == ["42"])
    }

    @Test func compilesDeleteWhereExistsWithCorrelatedSubqueryAndReturningAll() {
        let subquery = MutationTeamModel.query()
            .select(MutationTeamModel.id)
            .filter(MutationTeamModel.id == MutationTeamMemberModel.teamID)
            .filter(MutationTeamModel.ownerID == 11)
            .filter(MutationTeamModel.state == "archived")
        let rendered = MutationTeamMemberModel.delete().whereExists(subquery).returningAll().render()
        #expect(
            rendered.sql
                == #"DELETE FROM "team_members" WHERE EXISTS (SELECT "teams"."id" FROM "teams" WHERE "teams"."id" = "team_members"."team_id" AND "teams"."owner_id" = $1 AND "teams"."state" = $2) RETURNING *"#
        )
        #expect(rendered.binds.map(\.description) == ["11", "archived"])
    }

    @Test func compilesDeleteWhereNotExistsWithCorrelatedSubquery() {
        let subquery = MutationTeamMemberModel.query()
            .select(MutationTeamMemberModel.id)
            .filter(MutationTeamMemberModel.teamID == MutationTeamModel.id)
            .filter(MutationTeamMemberModel.role == "maintainer")
        let rendered = MutationTeamModel.delete().whereNotExists(subquery).filter(MutationTeamModel.ownerID == 3).render()
        #expect(
            rendered.sql
                == #"DELETE FROM "teams" WHERE NOT EXISTS (SELECT "team_members"."id" FROM "team_members" WHERE "team_members"."team_id" = "teams"."id" AND "team_members"."role" = $1) AND "teams"."owner_id" = $2"#
        )
        #expect(rendered.binds.map(\.description) == ["maintainer", "3"])
    }
}
