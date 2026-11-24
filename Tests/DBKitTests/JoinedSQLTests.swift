import DBKit
import Testing

/// Stops at the first query and reports its SQL, so no database is needed.
private struct CaptureExecutor: DatabaseExecutor {
    struct Captured: Error {
        let sql: String
    }

    let logger = Logger(label: "capture")

    func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        throw Captured(sql: query.sql)
    }
}

/// The SQL `all(on:)` sends first, which for a joined load is the one query that loads everything.
private func firstSQL<Row>(_ query: Query<Row>) async throws -> String {
    let captured = try await #require(throws: CaptureExecutor.Captured.self) {
        try await query.all(on: CaptureExecutor())
    }
    return captured.sql
}

/// rust-dbkit's `joined_sql.rs`, which checks that the query has a `JOIN`; these compare the whole SQL.
@Suite struct JoinedSQLTests {
    @Test func joinedHasManyUsesSingleJoinQuery() async throws {
        let query: Query<UserModel.Loaded<[TodoModel]>> = UserModel.query().with(\.todos, .joined)
        #expect(
            try await firstSQL(query)
                == #"SELECT "users".*, "todos"."id" AS "todos.id", "todos"."user_id" AS "todos.user_id", "todos"."title" AS "todos.title", "todos"."note" AS "todos.note", "todos"."is_complete" AS "todos.is_complete" FROM "users" LEFT JOIN "todos" ON "todos"."user_id" = "users"."id""#
        )
    }

    @Test func joinedBelongsToUsesSingleJoinQuery() async throws {
        let query: Query<TodoModel.Loaded<UserModel?, NotLoaded>> = TodoModel.query().with(\.user, .joined)
        #expect(
            try await firstSQL(query)
                == #"SELECT "todos".*, "users"."id" AS "user.id", "users"."name" AS "user.name", "users"."email" AS "user.email", "users"."region" AS "user.region" FROM "todos" LEFT JOIN "users" ON "users"."id" = "todos"."user_id""#
        )
    }

    @Test func joinedManyToManyUsesSingleJoinQuery() async throws {
        let query: Query<TodoModel.Loaded<NotLoaded, [TagModel]>> = TodoModel.query().with(\.tags, .joined)
        #expect(
            try await firstSQL(query)
                == #"SELECT "todos".*, "tags"."id" AS "tags.id", "tags"."name" AS "tags.name" FROM "todos" LEFT JOIN "todo_tags" ON "todo_tags"."todo_id" = "todos"."id" LEFT JOIN "tags" ON "tags"."id" = "todo_tags"."tag_id""#
        )
    }

    @Test func joinedNestedManyToManyUsesSingleJoinQuery() async throws {
        let query: Query<UserModel.Loaded<[TodoModel.Loaded<NotLoaded, [TagModel]>]>> = UserModel.query()
            .with(\.todos, .joined) { $0.with(\.tags, .joined) }
        #expect(
            try await firstSQL(query)
                == #"SELECT "users".*, "todos"."id" AS "todos.id", "todos"."user_id" AS "todos.user_id", "todos"."title" AS "todos.title", "todos"."note" AS "todos.note", "todos"."is_complete" AS "todos.is_complete", "tags"."id" AS "todos.tags.id", "tags"."name" AS "todos.tags.name" FROM "users" LEFT JOIN "todos" ON "todos"."user_id" = "users"."id" LEFT JOIN "todo_tags" ON "todo_tags"."todo_id" = "todos"."id" LEFT JOIN "tags" ON "tags"."id" = "todo_tags"."tag_id""#
        )
    }

    // Waits for slice 22: `joinedForUpdateScopesLockToBaseTable`, `with(\.todos, .joined).forUpdate(.noWait)` locking
    // `FOR UPDATE OF "users" NOWAIT`.
}
