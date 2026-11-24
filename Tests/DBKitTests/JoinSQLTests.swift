import DBKit
import Testing

/// rust-dbkit's `dbkit-core/join_sql.rs`. It writes the belongs-to condition as `todos.user_id = users.id`; this library
/// puts the joined table's column first in every relation join.
@Suite struct JoinSQLTests {
    @Test func compilesJoinFromRelation() {
        let query: Query<UserModel> = UserModel.query().join(\.todos)
        let rendered = query.render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" JOIN "todos" ON "todos"."user_id" = "users"."id""#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesLeftJoinFromRelation() {
        let query: Query<UserModel> = UserModel.query().leftJoin(\.todos)
        let rendered = query.render()
        #expect(rendered.sql == #"SELECT "users".* FROM "users" LEFT JOIN "todos" ON "todos"."user_id" = "users"."id""#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesJoinBelongsToRelation() {
        let query: Query<TodoModel> = TodoModel.query().join(\.user)
        let rendered = query.render()
        #expect(rendered.sql == #"SELECT "todos".* FROM "todos" JOIN "users" ON "users"."id" = "todos"."user_id""#)
        #expect(rendered.binds.isEmpty)
    }
}
