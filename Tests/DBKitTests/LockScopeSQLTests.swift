import DBKit
import Testing

/// rust-dbkit's `lock_scope_sql.rs`, which captures the SQL `all` sends; that SQL is `render()`'s.
@Suite struct LockScopeSQLTests {
    @Test func leftJoinForUpdateNowaitScopesLockToBaseTable() {
        let rendered = UserModel.query().leftJoin(\.todos).forUpdate(.noWait).render()
        #expect(
            rendered.sql
                == #"SELECT "users".* FROM "users" LEFT JOIN "todos" ON "todos"."user_id" = "users"."id" FOR UPDATE OF "users" NOWAIT"#
        )
    }
}
