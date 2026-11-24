import DBKit
import Testing

/// rust-dbkit's `dbkit-core/locking_sql.rs`. Its `skip_locked()` and `nowait()` are the argument of `forUpdate(_:)` here.
/// The lock is scoped to the query's own table only when the query has an outer join, whose nullable side PostgreSQL
/// can't lock; with inner joins `FOR UPDATE` locks the joined rows too.
@Suite struct LockingSQLTests {
    @Test func compilesForUpdateClause() {
        let rendered = UserModel.query().forUpdate().render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" FOR UPDATE"#)
        #expect(rendered.binds.isEmpty)
        #expect(UserModel.query().forUpdate(.wait).render().sql == rendered.sql)
    }

    @Test func compilesForUpdateSkipLockedClause() {
        let rendered = UserModel.query().forUpdate(.skipLocked).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" FOR UPDATE SKIP LOCKED"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesForUpdateNowaitClause() {
        let rendered = UserModel.query().forUpdate(.noWait).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" FOR UPDATE NOWAIT"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesLockingAfterOrderLimitOffset() {
        let rendered = UserModel.query()
            .filter(UserModel.email.ilike("%@example.com"))
            .orderBy(UserModel.id.asc)
            .limit(20)
            .offset(40)
            .forUpdate(.skipLocked)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "users".* FROM "users" WHERE "users"."email" ILIKE $1 ORDER BY "users"."id" ASC LIMIT 20 OFFSET 40 FOR UPDATE SKIP LOCKED"#
        )
        #expect(rendered.binds.map(\.description) == ["%@example.com"])
    }

    @Test func compilesLockingWhenForUpdateCalledBeforeOtherClauses() {
        let rendered = UserModel.query()
            .forUpdate(.skipLocked)
            .filter(UserModel.email.ilike("%@example.com"))
            .orderBy(UserModel.id.desc)
            .limit(10)
            .offset(5)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "users".* FROM "users" WHERE "users"."email" ILIKE $1 ORDER BY "users"."id" DESC LIMIT 10 OFFSET 5 FOR UPDATE SKIP LOCKED"#
        )
        #expect(rendered.binds.map(\.description) == ["%@example.com"])
    }

    @Test func compilesLockingWithJoinFilter() {
        let rendered = UserModel.query()
            .join(TodoModel.self, on: UserModel.id == TodoModel.userID)
            .filter(TodoModel.title == "Senior Rust Engineer")
            .forUpdate(.noWait)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "users".* FROM "users" JOIN "todos" ON "users"."id" = "todos"."user_id" WHERE "todos"."title" = $1 FOR UPDATE OF "users" NOWAIT"#
        )
        #expect(rendered.binds.map(\.description) == ["Senior Rust Engineer"])
    }

    @Test func compilesSelectOnlyWithLockingClause() {
        let rendered = UserModel.query().forUpdate().select(UserModel.id).render()
        #expect(rendered.sql == #"SELECT "users"."id" FROM "users" FOR UPDATE"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func forUpdateIsIdempotent() {
        let rendered = UserModel.query().forUpdate().forUpdate().render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" FOR UPDATE"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func skipLockedIsIdempotent() {
        let rendered = UserModel.query().forUpdate(.skipLocked).forUpdate(.skipLocked).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" FOR UPDATE SKIP LOCKED"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func nowaitIsIdempotent() {
        let rendered = UserModel.query().forUpdate(.noWait).forUpdate(.noWait).render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" FOR UPDATE NOWAIT"#)
        #expect(rendered.binds.isEmpty)
    }

    /// rust-dbkit checks the query it wraps; here it is the SQL `count(on:)` and `exists(on:)` send.
    @Test func compileWithoutPaginationOmitsLockingForCountExistsSubqueries() async throws {
        let query = UserModel.query()
            .filter(UserModel.email == "worker@example.com")
            .orderBy(UserModel.id.desc)
            .limit(5)
            .offset(10)
            .forUpdate(.skipLocked)

        let count = try await firstQuery { _ = try await query.count(on: $0) }
        #expect(count.sql == #"SELECT COUNT(*) FROM (SELECT "users".* FROM "users" WHERE "users"."email" = $1) AS "count""#)
        #expect(count.bindCount == 1)

        let exists = try await firstQuery { _ = try await query.exists(on: $0) }
        #expect(exists.sql == #"SELECT EXISTS (SELECT "users".* FROM "users" WHERE "users"."email" = $1)"#)
        #expect(exists.bindCount == 1)
    }

    /// rust-dbkit adds the joined loader's columns and joins to the compiled query; here a joined load shares the
    /// explicit inner join.
    @Test func compileWithExtraPreservesLockingClause() {
        let rendered = UserModel.query()
            .filter(UserModel.id == 42)
            .join(\.todos)
            .with(\.todos, .joined)
            .forUpdate(.noWait)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "users".*, "todos"."id" AS "todos.id", "todos"."user_id" AS "todos.user_id", "todos"."title" AS "todos.title", "todos"."note" AS "todos.note", "todos"."is_complete" AS "todos.is_complete" FROM "users" JOIN "todos" ON "todos"."user_id" = "users"."id" WHERE "users"."id" = $1 FOR UPDATE OF "users" NOWAIT"#
        )
        #expect(rendered.binds.map(\.description) == ["42"])
    }

    @Test func compileWithExtraLeftJoinScopesLockToBaseTable() {
        let rendered = UserModel.query().filter(UserModel.id == 7).with(\.todos, .joined).forUpdate(.noWait).render()
        #expect(
            rendered.sql
                == #"SELECT "users".*, "todos"."id" AS "todos.id", "todos"."user_id" AS "todos.user_id", "todos"."title" AS "todos.title", "todos"."note" AS "todos.note", "todos"."is_complete" AS "todos.is_complete" FROM "users" LEFT JOIN "todos" ON "todos"."user_id" = "users"."id" WHERE "users"."id" = $1 FOR UPDATE OF "users" NOWAIT"#
        )
        #expect(rendered.binds.map(\.description) == ["7"])
    }

    @Test func compilesDirectLeftJoinForUpdateScopesLockToBaseTable() {
        let rendered = UserModel.query().leftJoin(TodoModel.self, on: UserModel.id == TodoModel.userID).forUpdate().render()
        #expect(
            rendered.sql == #"SELECT "users".* FROM "users" LEFT JOIN "todos" ON "users"."id" = "todos"."user_id" FOR UPDATE OF "users""#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesDirectLeftJoinForUpdateSkipLockedScopesLockToBaseTable() {
        let rendered = UserModel.query()
            .leftJoin(TodoModel.self, on: UserModel.id == TodoModel.userID)
            .forUpdate(.skipLocked)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "users".* FROM "users" LEFT JOIN "todos" ON "users"."id" = "todos"."user_id" FOR UPDATE OF "users" SKIP LOCKED"#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesDirectLeftJoinForUpdateNowaitScopesLockToBaseTable() {
        let rendered = UserModel.query().leftJoin(TodoModel.self, on: UserModel.id == TodoModel.userID).forUpdate(.noWait).render()
        #expect(
            rendered.sql
                == #"SELECT "users".* FROM "users" LEFT JOIN "todos" ON "users"."id" = "todos"."user_id" FOR UPDATE OF "users" NOWAIT"#
        )
        #expect(rendered.binds.isEmpty)
    }
}
