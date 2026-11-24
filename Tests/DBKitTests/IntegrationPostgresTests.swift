import DBKit
import Foundation
import Testing

/// rust-dbkit's `LockRow`, once per locking test that needs a real table, without its `token`.
@Model(table: "blocking_lock_rows")
class BlockingLockRowModel {
    @Key @AutoIncrement var id: Int64
    var note: String
}

@Model(table: "skip_locked_rows")
class SkipLockedRowModel {
    @Key @AutoIncrement var id: Int64
    var note: String
}

@Model(table: "nowait_lock_rows")
class NoWaitLockRowModel {
    @Key @AutoIncrement var id: Int64
    var note: String
}

@Model(table: "limit_lock_rows")
class LimitLockRowModel {
    @Key @AutoIncrement var id: Int64
    var note: String
}

@Suite struct IntegrationPostgresTests {
    @Test func insertUpdateDeleteRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Alex", email: "a@b.com")
            #expect(user.id > 0)
            #expect(user.name == "Alex")

            let updated = try await UserModel.update()
                .set(UserModel.name, to: "Updated")
                .filter(UserModel.id == user.id)
                .returningAll()
                .all(on: tx)
            #expect(updated.count == 1)
            #expect(updated.first?.name == "Updated")

            let deleted = try await UserModel.delete().filter(UserModel.id == user.id).execute(on: tx)
            #expect(deleted == 1)
            #expect(try await UserModel.query().all(on: tx).isEmpty)
        }
    }

    @Test func renamedColumnsRoundtripThroughCrudFiltersAndJoinedLoads() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let parent = try await seedRenamedParent(on: tx, kind: "primary", externalReference: "ref-1", label: "Example")
            #expect(parent.kind == "primary")
            #expect(parent.externalReference == "ref-1")
            #expect(parent.label == "Example")

            let child = try await seedRenamedChild(on: tx, parentID: parent.id, kind: "child", rankKey: 10)
            #expect(child.kind == "child")
            #expect(child.rankKey == 10)

            let filtered = try #require(
                try await RenamedParentModel.query()
                    .filter(RenamedParentModel.kind == "primary")
                    .filter(RenamedParentModel.externalReference == "ref-1")
                    .first(on: tx))
            #expect(filtered.id == parent.id)
            #expect(filtered.kind == "primary")

            let updatedRows = try await RenamedParentModel.update()
                .set(RenamedParentModel.kind, to: "secondary")
                .set(RenamedParentModel.externalReference, to: "ref-2")
                .filter(RenamedParentModel.id == parent.id)
                .returningAll()
                .all(on: tx)
            #expect(updatedRows.count == 1)
            let updated = try #require(updatedRows.first)
            #expect(updated.kind == "secondary")
            #expect(updated.externalReference == "ref-2")

            let loaded = try #require(
                try await RenamedParentModel.query()
                    .filter(RenamedParentModel.id == parent.id)
                    .with(\.children, .joined)
                    .first(on: tx))
            #expect(loaded.kind == "secondary")
            #expect(loaded.externalReference == "ref-2")
            #expect(loaded.children.count == 1)
            #expect(loaded.children.first?.kind == "child")
            #expect(loaded.children.first?.rankKey == 10)
        }
    }

    @Test func insertManyInsertsMultipleRows() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let inserted = try await UserModel.insert([
                UserModel.Insert(name: "Alpha", email: "alpha@db.com"),
                UserModel.Insert(name: "Beta", email: "beta@db.com"),
            ])
            .execute(on: tx)
            #expect(inserted == 2)

            let users = try await UserModel.query().orderBy(UserModel.id.asc).all(on: tx)
            #expect(users.map(\.name) == ["Alpha", "Beta"])
        }
    }

    @Test func onConflictDoNothingIgnoresDuplicateCompositeKey() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let original = try await seedRunPayload(on: tx, 100, 200, payload: "payload-v1", source: "ingest-a", version: 1)
            #expect(original.payload == "payload-v1")

            let affected = try await RunPayloadModel.insert(
                RunPayloadModel.Insert(targetID: 100, runID: 200, payload: "payload-v2", source: "ingest-b", version: 2)
            )
            .onConflictDoNothing(RunPayloadModel.targetID, RunPayloadModel.runID)
            .execute(on: tx)
            #expect(affected == 0)

            let rows = try await runPayloads(100, 200, on: tx)
            #expect(rows.count == 1)
            #expect(rows.first?.payload == "payload-v1")
            #expect(rows.first?.source == "ingest-a")
            #expect(rows.first?.version == 1)
        }
    }

    @Test func onConflictDoNothingWithReturningAllReturnsNoneOnConflict() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedRunPayload(on: tx, 10, 20, payload: "payload-v1", source: "ingest-a", version: 1)

            let row = try await RunPayloadModel.insert(
                RunPayloadModel.Insert(targetID: 10, runID: 20, payload: "payload-v2", source: "ingest-b", version: 2)
            )
            .onConflictDoNothing(RunPayloadModel.targetID, RunPayloadModel.runID)
            .returningAll()
            .first(on: tx)
            #expect(row == nil)
        }
    }

    @Test func onConflictDoUpdateUpdatesOnlySelectedColumnsOnConflict() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedRunPayload(on: tx, 500, 600, payload: "payload-v1", source: "ingest-a", version: 1)

            let affected = try await RunPayloadModel.insert(
                RunPayloadModel.Insert(targetID: 500, runID: 600, payload: "payload-v2", source: "ingest-b", version: 2)
            )
            .onConflict(RunPayloadModel.targetID, RunPayloadModel.runID, doUpdate: RunPayloadModel.payload, RunPayloadModel.version)
            .execute(on: tx)
            #expect(affected == 1)

            let rows = try await runPayloads(500, 600, on: tx)
            #expect(rows.count == 1)
            #expect(rows.first?.payload == "payload-v2")
            #expect(rows.first?.version == 2)
            #expect(rows.first?.source == "ingest-a")
        }
    }

    @Test func onConflictDoUpdateInsertsWhenNoConflictExists() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let affected = try await RunPayloadModel.insert(
                RunPayloadModel.Insert(targetID: 700, runID: 800, payload: "payload-v1", source: "ingest-a", version: 1)
            )
            .onConflict(RunPayloadModel.targetID, RunPayloadModel.runID, doUpdate: RunPayloadModel.payload, RunPayloadModel.version)
            .execute(on: tx)
            #expect(affected == 1)

            let rows = try await runPayloads(700, 800, on: tx)
            #expect(rows.count == 1)
            #expect(rows.first?.payload == "payload-v1")
            #expect(rows.first?.source == "ingest-a")
            #expect(rows.first?.version == 1)
        }
    }

    @Test func modelDeleteRemovesRow() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Delete", email: "delete2@db.com")
            let deleted = try await user.delete(on: tx)
            #expect(deleted == 1)
            #expect(try await UserModel.find(user.id, on: tx) == nil)
        }
    }

    @Test func selectinHasManyLoadsChildren() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Riley", email: "r@b.com")
            _ = try await seedTodo(on: tx, userID: user.id, title: "Write tests")
            _ = try await seedTodo(on: tx, userID: user.id, title: "Ship code")

            let users: [UserModel.Loaded<[TodoModel]>] = try await UserModel.query()
                .filter(UserModel.id == user.id)
                .with(\.todos)
                .all(on: tx)

            #expect(users.count == 1)
            #expect(users[0].todos.map(\.title).sorted() == ["Ship code", "Write tests"])
        }
    }

    @Test func selectinBelongsToLoadsParent() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Dana", email: "d@b.com")
            let todo = try await seedTodo(on: tx, userID: user.id, title: "Map relations")

            let todos: [TodoModel.Loaded<UserModel?, NotLoaded>] = try await TodoModel.query()
                .filter(TodoModel.id == todo.id)
                .with(\.user)
                .all(on: tx)

            #expect(todos.count == 1)
            let loaded = try #require(todos[0].user)
            #expect(loaded.id == user.id)
            #expect(loaded.email == "d@b.com")
        }
    }

    @Test func joinedHasManyLoadsChildren() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Joined", email: "joined@db.com")
            _ = try await seedTodo(on: tx, userID: user.id, title: "Joined A")
            _ = try await seedTodo(on: tx, userID: user.id, title: "Joined B")

            let users: [UserModel.Loaded<[TodoModel]>] = try await UserModel.query()
                .filter(UserModel.id == user.id)
                .with(\.todos, .joined)
                .all(on: tx)

            #expect(users.count == 1)
            #expect(users[0].todos.map(\.title).sorted() == ["Joined A", "Joined B"])
        }
    }

    @Test func joinedHasManyIncludesEmptyChildren() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Empty", email: "empty@db.com")

            let users: [UserModel.Loaded<[TodoModel]>] = try await UserModel.query()
                .filter(UserModel.id == user.id)
                .with(\.todos, .joined)
                .all(on: tx)

            #expect(users.count == 1)
            #expect(users[0].todos.isEmpty)
        }
    }

    @Test func joinedHasManyFiltersChildrenWhenJoinFiltered() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Filter", email: "filter@db.com")
            _ = try await seedTodo(on: tx, userID: user.id, title: "Keep")
            _ = try await seedTodo(on: tx, userID: user.id, title: "Drop")

            let users: [UserModel.Loaded<[TodoModel]>] = try await UserModel.query()
                .join(\.todos)
                .filter(TodoModel.title == "Keep")
                .distinct()
                .with(\.todos, .joined)
                .all(on: tx)

            #expect(users.count == 1)
            #expect(users[0].todos.count == 1)
            #expect(users[0].todos.first?.title == "Keep")
        }
    }

    @Test func joinedBelongsToLoadsParent() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Joined Parent", email: "joined-parent@db.com")
            let todo = try await seedTodo(on: tx, userID: user.id, title: "Joined child")

            let todos: [TodoModel.Loaded<UserModel?, NotLoaded>] = try await TodoModel.query()
                .filter(TodoModel.id == todo.id)
                .with(\.user, .joined)
                .all(on: tx)

            #expect(todos.count == 1)
            let loaded = try #require(todos[0].user)
            #expect(loaded.id == user.id)
            #expect(loaded.email == "joined-parent@db.com")
        }
    }

    @Test func joinedNestedFiltersChildrenWhenJoinFiltered() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Nested", email: "nested@db.com")
            let todoKeep = try await seedTodo(on: tx, userID: user.id, title: "Keep")
            let todoDrop = try await seedTodo(on: tx, userID: user.id, title: "Drop")
            let tagA = try await seedTag(on: tx, name: "A")
            let tagB = try await seedTag(on: tx, name: "B")
            try await seedTodoTag(on: tx, todoID: todoKeep.id, tagID: tagA.id)
            try await seedTodoTag(on: tx, todoID: todoDrop.id, tagID: tagB.id)

            let users: [UserModel.Loaded<[TodoModel.Loaded<NotLoaded, [TagModel]>]>] = try await UserModel.query()
                .join(\.todos)
                .filter(TodoModel.title == "Keep")
                .distinct()
                .with(\.todos, .joined) { $0.with(\.tags, .joined) }
                .all(on: tx)

            #expect(users.count == 1)
            #expect(users[0].todos.count == 1)
            #expect(users[0].todos.first?.title == "Keep")
            #expect(users[0].todos.first?.tags.count == 1)
            #expect(users[0].todos.first?.tags.first?.name == "A")
        }
    }

    @Test func joinedManyToManyFiltersChildrenWhenJoinFiltered() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Tags", email: "tags@db.com")
            let todo = try await seedTodo(on: tx, userID: user.id, title: "Tagged")
            let tagA = try await seedTag(on: tx, name: "A")
            let tagB = try await seedTag(on: tx, name: "B")
            try await seedTodoTag(on: tx, todoID: todo.id, tagID: tagA.id)
            try await seedTodoTag(on: tx, todoID: todo.id, tagID: tagB.id)

            let todos: [TodoModel.Loaded<NotLoaded, [TagModel]>] = try await TodoModel.query()
                .join(\.tags)
                .filter(TagModel.name == "A")
                .distinct()
                .with(\.tags, .joined)
                .all(on: tx)

            #expect(todos.count == 1)
            #expect(todos[0].tags.count == 1)
            #expect(todos[0].tags.first?.name == "A")
        }
    }

    @Test func nestedSelectinLoads() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Jo", email: "jo@b.com")
            _ = try await seedTodo(on: tx, userID: user.id, title: "Chain loads")

            let users: [UserModel.Loaded<[TodoModel.Loaded<UserModel?, NotLoaded>]>] = try await UserModel.query()
                .filter(UserModel.id == user.id)
                .with(\.todos) { $0.with(\.user) }
                .all(on: tx)

            #expect(users.count == 1)
            #expect(users[0].todos.count == 1)
            let nestedUser = try #require(users[0].todos[0].user)
            #expect(nestedUser.id == user.id)
        }
    }

    @Test func lazyLoadRelation() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Ari", email: "ari@b.com")
            _ = try await seedTodo(on: tx, userID: user.id, title: "Lazy load")

            let loaded: UserModel.Loaded<[TodoModel]> = try await user.load(\.todos, on: tx)

            #expect(loaded.todos.count == 1)
            #expect(loaded.todos[0].title == "Lazy load")
        }
    }

    @Test func joinFilterOnChildTable() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let userKeep = try await seedUser(on: tx, name: "Keep", email: "keep@db.com")
            let userDrop = try await seedUser(on: tx, name: "Drop", email: "drop@db.com")
            _ = try await seedTodo(on: tx, userID: userKeep.id, title: "Keep me")
            _ = try await seedTodo(on: tx, userID: userKeep.id, title: "Also me")
            _ = try await seedTodo(on: tx, userID: userDrop.id, title: "Ignore me")

            let users = try await UserModel.query()
                .join(\.todos)
                .filter(TodoModel.title == "Keep me")
                .distinct()
                .all(on: tx)

            #expect(users.count == 1)
            #expect(users.first?.id == userKeep.id)
        }
    }

    @Test func manyToManySelectinLoadsChildren() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Tagger", email: "tagger@db.com")
            let todo1 = try await seedTodo(on: tx, userID: user.id, title: "First")
            let todo2 = try await seedTodo(on: tx, userID: user.id, title: "Second")
            let tagA = try await seedTag(on: tx, name: "A")
            let tagB = try await seedTag(on: tx, name: "B")
            try await seedTodoTag(on: tx, todoID: todo1.id, tagID: tagA.id)
            try await seedTodoTag(on: tx, todoID: todo1.id, tagID: tagB.id)
            try await seedTodoTag(on: tx, todoID: todo2.id, tagID: tagB.id)

            let todos: [TodoModel.Loaded<NotLoaded, [TagModel]>] = try await TodoModel.query()
                .filter(TodoModel.userID == user.id)
                .with(\.tags)
                .all(on: tx)

            #expect(todos.count == 2)
            let tags1 = try #require(todos.first { $0.id == todo1.id }).tags
            #expect(tags1.map(\.name).sorted() == ["A", "B"])
            let tags2 = try #require(todos.first { $0.id == todo2.id }).tags
            #expect(tags2.map(\.name).sorted() == ["B"])
        }
    }

    @Test func manyToManySelectinReverseLoadsParents() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Tagger", email: "tagger2@db.com")
            let todo1 = try await seedTodo(on: tx, userID: user.id, title: "First")
            let todo2 = try await seedTodo(on: tx, userID: user.id, title: "Second")
            let tagA = try await seedTag(on: tx, name: "A")
            let tagB = try await seedTag(on: tx, name: "B")
            try await seedTodoTag(on: tx, todoID: todo1.id, tagID: tagA.id)
            try await seedTodoTag(on: tx, todoID: todo1.id, tagID: tagB.id)
            try await seedTodoTag(on: tx, todoID: todo2.id, tagID: tagB.id)

            let tags: [TagModel.Loaded<[TodoModel]>] = try await TagModel.query().with(\.todos).all(on: tx)

            let todosA = try #require(tags.first { $0.id == tagA.id }).todos
            #expect(todosA.map(\.title).sorted() == ["First"])
            let todosB = try #require(tags.first { $0.id == tagB.id }).todos
            #expect(todosB.map(\.title).sorted() == ["First", "Second"])
        }
    }

    @Test func manyToManyJoinFilter() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Joiner", email: "joiner@db.com")
            let todo1 = try await seedTodo(on: tx, userID: user.id, title: "First")
            let todo2 = try await seedTodo(on: tx, userID: user.id, title: "Second")
            let tagA = try await seedTag(on: tx, name: "A")
            let tagB = try await seedTag(on: tx, name: "B")
            try await seedTodoTag(on: tx, todoID: todo1.id, tagID: tagA.id)
            try await seedTodoTag(on: tx, todoID: todo2.id, tagID: tagB.id)

            let todos = try await TodoModel.query().join(\.tags).filter(TagModel.name == "B").distinct().all(on: tx)

            #expect(todos.count == 1)
            #expect(todos.first?.id == todo2.id)
        }
    }

    @Test func manyToManyLazyLoad() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Lazy", email: "lazy@db.com")
            let todo = try await seedTodo(on: tx, userID: user.id, title: "First")
            let tag = try await seedTag(on: tx, name: "A")
            try await seedTodoTag(on: tx, todoID: todo.id, tagID: tag.id)

            let loaded: TodoModel.Loaded<NotLoaded, [TagModel]> = try await todo.load(\.tags, on: tx)

            #expect(loaded.tags.count == 1)
            #expect(loaded.tags[0].name == "A")
        }
    }

    @Test func activeInsertRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            var active = ActiveModel<UserModel>()
            active.name = "Active"
            active.email = "active@db.com"

            let inserted: UserModel = try await active.save(on: tx)
            #expect(inserted.id > 0)
            #expect(inserted.name == "Active")
            #expect(inserted.email == "active@db.com")
        }
    }

    @Test func activeSaveInsertsNewActiveEvenWithPrimaryKeySet() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            var active = ActiveModel<OrderLineModel>()
            active.orderID = 7
            active.lineID = 8
            active.note = "Saved"

            let inserted = try await active.save(on: tx)
            #expect(inserted.orderID == 7)
            #expect(inserted.lineID == 8)
            #expect(inserted.note == "Saved")

            let fetched = try #require(try await orderLine(7, 8, on: tx))
            #expect(fetched.note == "Saved")
        }
    }

    @Test func activeSaveUpdatesLoadedModels() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Before Save", email: "before-save@db.com")
            var active = user.active()
            active.name = "After Save"

            let saved = try await active.save(on: tx)
            #expect(saved.id == user.id)
            #expect(saved.name == "After Save")
            #expect(saved.email == user.email)

            let fetched = try #require(try await UserModel.find(user.id, on: tx))
            #expect(fetched.name == "After Save")
            #expect(fetched.email == user.email)
        }
    }

    @Test func activeSaveLoadedWithoutChangesIsNoop() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "No Change", email: "no-change@db.com")
            let active = user.active()

            let saved = try await active.save(on: tx)
            #expect(saved.id == user.id)
            #expect(saved.name == "No Change")
            #expect(saved.email == user.email)

            let fetched = try #require(try await UserModel.find(user.id, on: tx))
            #expect(fetched.name == "No Change")
            #expect(fetched.email == user.email)
        }
    }

    @Test func activeSaveMissingRequiredFieldsErrorsOnInsert() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            var active = ActiveModel<UserModel>()
            active.name = "Missing email"

            await #expect(throws: (any Error).self) { try await active.save(on: tx) }
        }
    }

    /// rust-dbkit never writes key columns and reports the row as not found instead; see `docs/rust-parity.md`.
    @Test func activeSaveChangingACompositeKeyColumnMovesTheRow() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row = try await seedOrderLine(on: tx, 5, 5, note: "Orig")
            var active = row.active()
            active.lineID = 9
            active.note = "Changed"

            let saved = try await active.save(on: tx)
            #expect(saved.orderID == 5 && saved.lineID == 9 && saved.note == "Changed")

            #expect(try await orderLine(5, 5, on: tx) == nil)
            #expect(try await orderLine(5, 9, on: tx)?.note == "Changed")
        }
    }

    @Test func activeUpdateFromLoaded() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Before", email: "before@db.com")
            var active = user.active()
            active.name = "After"

            let updated: UserModel = try await active.update(on: tx)
            #expect(updated.id == user.id)
            #expect(updated.name == "After")
            #expect(updated.email == user.email)
        }
    }

    /// A concurrent update to another column survives, since an active model writes only the columns assigned on it.
    @Test func activeUpdateDoesNotOverwriteOtherFields() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Before", email: "before@db.com")
            var active = user.active()

            try await UserModel.update().set(UserModel.email, to: "updated@db.com").filter(UserModel.id == user.id).execute(on: tx)

            active.name = "After"
            _ = try await active.update(on: tx)

            let fetched = try #require(try await UserModel.find(user.id, on: tx))
            #expect(fetched.name == "After")
            #expect(fetched.email == "updated@db.com")
        }
    }

    @Test func activeUpdateSetNull() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row = try #require(
                try await NullableRowModel.insert(NullableRowModel.Insert(note: "note")).returningAll().first(on: tx))
            var active = row.active()
            active.note = nil

            let updated: NullableRowModel = try await active.update(on: tx)
            #expect(updated.id == row.id)
            #expect(updated.note == nil)
        }
    }

    /// Updating a new active model is a mistake; whether it traps or throws, it never succeeds.
    @Test func activeUpdateRequiresPrimaryKey() async {
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var active = ActiveModel<UserModel>()
                active.name = "No PK"
                active.email = "no-pk@db.com"
                _ = try await active.update(on: tx)
            }
        }
    }

    @Test func activeUpdateUsesOnlyPrimaryKeyFilter() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Before", email: "before@db.com")
            let untouched = try await seedUser(on: tx, name: "Other", email: "other@db.com")
            var active = user.active()
            active.name = "After"
            active.email = "after@db.com"

            let updated = try await active.update(on: tx)
            #expect(updated.id == user.id)
            #expect(updated.name == "After")
            #expect(updated.email == "after@db.com")

            let fetched = try #require(try await UserModel.find(user.id, on: tx))
            #expect(fetched.name == "After")
            #expect(fetched.email == "after@db.com")

            let other = try #require(try await UserModel.find(untouched.id, on: tx))
            #expect(other.name == "Other")
            #expect(other.email == "other@db.com")
        }
    }

    @Test func compositePrimaryKeyActiveUpdateUsesBothKeys() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let first = try await seedOrderLine(on: tx, 1, 1, note: "A")
            _ = try await seedOrderLine(on: tx, 1, 2, note: "B")
            _ = try await seedOrderLine(on: tx, 2, 1, note: "C")

            var active = first.active()
            active.note = "A1"
            let updated = try await active.update(on: tx)
            #expect(updated.orderID == 1)
            #expect(updated.lineID == 1)
            #expect(updated.note == "A1")

            #expect(try await orderLine(1, 1, on: tx)?.note == "A1")
            #expect(try await orderLine(1, 2, on: tx)?.note == "B")
            #expect(try await orderLine(2, 1, on: tx)?.note == "C")
        }
    }

    @Test func compositePrimaryKeyActiveUpdateRequiresAllKeys() async {
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var missingLine = ActiveModel<OrderLineModel>()
                missingLine.orderID = 1
                missingLine.note = "Missing line"
                _ = try await missingLine.update(on: tx)
            }
        }
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var missingOrder = ActiveModel<OrderLineModel>()
                missingOrder.lineID = 1
                missingOrder.note = "Missing order"
                _ = try await missingOrder.update(on: tx)
            }
        }
    }

    /// Each insert runs in its own transaction, since a failed statement aborts the transaction it runs in.
    @Test func compositePrimaryKeyActiveInsertRequiresAllKeys() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            var missingLine = ActiveModel<OrderLineModel>()
            missingLine.orderID = 1
            missingLine.note = "Missing line"
            await #expect(throws: (any Error).self) { try await missingLine.save(on: tx) }
        }
        try await withRollback { tx in
            try await setupSchema(on: tx)
            var missingOrder = ActiveModel<OrderLineModel>()
            missingOrder.lineID = 1
            missingOrder.note = "Missing order"
            await #expect(throws: (any Error).self) { try await missingOrder.save(on: tx) }
        }
    }

    @Test func activeDeleteRemovesOnlyTarget() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Delete", email: "delete@db.com")
            let other = try await seedUser(on: tx, name: "Keep", email: "keep@db.com")

            let deleted = try await user.active().delete(on: tx)
            #expect(deleted == 1)

            #expect(try await UserModel.find(user.id, on: tx) == nil)
            #expect(try await UserModel.find(other.id, on: tx)?.email == "keep@db.com")
        }
    }

    @Test func activeDeleteRequiresPrimaryKey() async {
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var active = ActiveModel<UserModel>()
                active.name = "No PK"
                active.email = "no-pk@db.com"
                _ = try await active.delete(on: tx)
            }
        }
    }

    @Test func compositePrimaryKeyActiveDeleteUsesBothKeys() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let target = try await seedOrderLine(on: tx, 1, 1, note: "A")
            _ = try await seedOrderLine(on: tx, 1, 2, note: "B")
            _ = try await seedOrderLine(on: tx, 2, 1, note: "C")

            let deleted = try await target.active().delete(on: tx)
            #expect(deleted == 1)

            #expect(try await orderLine(1, 1, on: tx) == nil)
            #expect(try await orderLine(1, 2, on: tx)?.note == "B")
            #expect(try await orderLine(2, 1, on: tx)?.note == "C")
        }
    }

    @Test func compositePrimaryKeyActiveDeleteRequiresAllKeys() async {
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var missingLine = ActiveModel<OrderLineModel>()
                missingLine.orderID = 1
                missingLine.note = "Missing line"
                _ = try await missingLine.delete(on: tx)
            }
        }
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var missingOrder = ActiveModel<OrderLineModel>()
                missingOrder.lineID = 1
                missingOrder.note = "Missing order"
                _ = try await missingOrder.delete(on: tx)
            }
        }
    }

    @Test func compositePrimaryKeyModelDeleteRemovesRow() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let target = try await seedOrderLine(on: tx, 9, 9, note: "Z")

            let deleted = try await target.delete(on: tx)
            #expect(deleted == 1)

            #expect(try await orderLine(target.orderID, target.lineID, on: tx) == nil)
        }
    }

    /// `Date` stands in for the `timestamp` and `date` values; rust-dbkit's `time` column has no Swift type.
    @Test func uuidDateTimeRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let day = isoDate("2024-01-02T00:00:00Z")
            let startsAt = isoDate("2024-01-02T03:04:05Z")
            let id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

            let inserted = try #require(
                try await EventModel.insert(EventModel.Insert(id: id, name: "Launch", startsAt: startsAt, day: day)).returningAll().first(
                    on: tx))
            #expect(inserted.id == id)
            #expect(inserted.startsAt == startsAt)
            #expect(inserted.day == day)

            let found = try #require(
                try await EventModel.query()
                    .filter(EventModel.id == id)
                    .filter(EventModel.day == day)
                    .filter(EventModel.startsAt == startsAt)
                    .first(on: tx))
            #expect(found.id == id)
            #expect(found.name == "Launch")
            #expect(found.startsAt == startsAt)
            #expect(found.day == day)
        }
    }

    @Test func arrayColumnRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let tags = ["alpha", "beta"]
            let inserted = try #require(try await ProfileModel.insert(ProfileModel.Insert(tags: tags)).returningAll().first(on: tx))
            #expect(inserted.tags == tags)

            let matched = try await ProfileModel.query().filter(ProfileModel.tags == tags).all(on: tx)
            #expect(matched.map(\.id) == [inserted.id])

            let updatedTags = ["gamma", "delta"]
            var active = inserted.active()
            active.tags = updatedTags
            let updated = try await active.update(on: tx)
            #expect(updated.tags == updatedTags)

            let fetched = try #require(try await ProfileModel.find(updated.id, on: tx))
            #expect(fetched.tags == updatedTags)
        }
    }

    @Test func jsonColumnRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let payload = JSONPayload(name: "alpha", active: true)
            let inserted = try #require(try await JSONRowModel.insert(JSONRowModel.Insert(data: payload)).returningAll().first(on: tx))
            #expect(inserted.data == payload)

            let matched = try await JSONRowModel.query().filter(JSONRowModel.data == payload).all(on: tx)
            #expect(matched.map(\.id) == [inserted.id])

            let updatedPayload = JSONPayload(name: "beta", active: false)
            var active = inserted.active()
            active.data = updatedPayload
            let updated = try await active.update(on: tx)
            #expect(updated.data == updatedPayload)

            let fetched = try #require(try await JSONRowModel.find(updated.id, on: tx))
            #expect(fetched.data == updatedPayload)
        }
    }

    /// rust-dbkit's borrowed values are plain `String?` constants here; Swift doesn't distinguish owned and borrowed.
    @Test func insertUpdateAndFilterNulls() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let inserted = try await seedNullableRow(on: tx, note: nil)
            #expect(inserted.note == nil)

            let someRow = try await seedNullableRow(on: tx, note: "hello")
            #expect(someRow.note == "hello")

            func setNote(_ note: String?) async throws -> [NullableRowModel] {
                try await NullableRowModel.update()
                    .set(NullableRowModel.note, to: note)
                    .filter(NullableRowModel.id == someRow.id)
                    .returningAll()
                    .all(on: tx)
            }

            var updated = try await NullableRowModel.update()
                .set(NullableRowModel.note, to: "direct")
                .filter(NullableRowModel.id == someRow.id)
                .returningAll()
                .all(on: tx)
            #expect(updated.first?.note == "direct")

            let optional: String? = "optional"
            updated = try await setNote(optional)
            #expect(updated.first?.note == "optional")

            let directMatch = try #require(try await NullableRowModel.query().filter(NullableRowModel.note == "optional").first(on: tx))
            #expect(directMatch.id == someRow.id)

            let optionalMatch = try #require(try await NullableRowModel.query().filter(NullableRowModel.note == optional).first(on: tx))
            #expect(optionalMatch.id == someRow.id)

            let borrowedOptional: String? = "borrowed"
            updated = try await setNote(borrowedOptional)
            #expect(updated.first?.note == "borrowed")

            let borrowedMatch = try #require(
                try await NullableRowModel.query().filter(NullableRowModel.note == borrowedOptional).first(on: tx))
            #expect(borrowedMatch.id == someRow.id)

            let borrowedNone: String? = nil
            updated = try await setNote(borrowedNone)
            #expect(updated.first?.note == nil)

            let borrowedNullMatch = try await NullableRowModel.query().filter(NullableRowModel.note == borrowedNone).all(on: tx)
            #expect(borrowedNullMatch.count == 2)

            updated = try await NullableRowModel.update()
                .set(NullableRowModel.note, to: nil)
                .filter(NullableRowModel.id == someRow.id)
                .returningAll()
                .all(on: tx)
            #expect(updated.count == 1)
            #expect(updated.first?.note == nil)

            let nullRows = try await NullableRowModel.query().filter(NullableRowModel.note == nil).all(on: tx)
            #expect(nullRows.count == 2)
            #expect(nullRows.allSatisfy { $0.note == nil })
        }
    }

    /// Rows decode into a `Decodable` struct by alias; rust-dbkit selects `note` without an alias, which `select` can't
    /// mix with aliased expressions, so it is aliased `note`.
    @Test func nullableValueComparisonProjectionsFollowPostgresThreeValuedLogic() async throws {
        struct ComparisonRow: Decodable {
            let note: String?
            let equalsDirect: Bool?
            let equalsOptional: Bool?
            let equalsNull: Bool?
            let differsDirect: Bool?
            let differsNull: Bool?
            let less: Bool?
            let lessOrEqual: Bool?
            let greater: Bool?
            let greaterOrEqual: Bool?
            let between: Bool?
            let matches: Bool?
            let matchesCaseInsensitively: Bool?
            let listed: Bool?
            let optionalList: Bool?
            let emptyList: Bool?
            let isNull: Bool
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            for note in [nil, "alpha", "middle", "zulu"] {
                _ = try await seedNullableRow(on: tx, note: note)
            }

            let middle: String? = "middle"
            let rows = try await NullableRowModel.query()
                .select(
                    NullableRowModel.note.as("note"),
                    (NullableRowModel.note == "middle").as("equals_direct"),
                    (NullableRowModel.note == middle).as("equals_optional"),
                    (NullableRowModel.note == nil).as("equals_null"),
                    (NullableRowModel.note != "middle").as("differs_direct"),
                    (NullableRowModel.note != nil).as("differs_null"),
                    (NullableRowModel.note < "middle").as("less"),
                    (NullableRowModel.note <= "middle").as("less_or_equal"),
                    (NullableRowModel.note > "middle").as("greater"),
                    (NullableRowModel.note >= "middle").as("greater_or_equal"),
                    NullableRowModel.note.between("b", "y").as("between"),
                    NullableRowModel.note.like("m%").as("matches"),
                    NullableRowModel.note.ilike("M%").as("matches_case_insensitively"),
                    NullableRowModel.note.in(["alpha", "middle"]).as("listed"),
                    NullableRowModel.note.in(["alpha", nil]).as("optional_list"),
                    NullableRowModel.note.in([]).as("empty_list"),
                    NullableRowModel.note.isNull.as("is_null")
                )
                .orderBy(NullableRowModel.id.asc)
                .all(as: ComparisonRow.self, on: tx)

            #expect(rows.map(\.note) == [nil, "alpha", "middle", "zulu"])
            #expect(rows.map(\.equalsDirect) == [nil, false, true, false])
            #expect(rows.map(\.equalsOptional) == [nil, false, true, false])
            #expect(rows.map(\.equalsNull) == [true, false, false, false])
            #expect(rows.map(\.differsDirect) == [nil, true, false, true])
            #expect(rows.map(\.differsNull) == [false, true, true, true])

            #expect(rows.map(\.less) == [nil, true, false, false])
            #expect(rows.map(\.lessOrEqual) == [nil, true, true, false])
            #expect(rows.map(\.greater) == [nil, false, false, true])
            #expect(rows.map(\.greaterOrEqual) == [nil, false, true, true])
            #expect(rows.map(\.between) == [nil, false, true, false])

            #expect(rows.map(\.matches) == [nil, false, true, false])
            #expect(rows.map(\.matchesCaseInsensitively) == [nil, false, true, false])
            #expect(rows.map(\.listed) == [nil, true, true, false])
            #expect(rows.map(\.optionalList) == [nil, true, nil, nil])
            #expect(rows.map(\.emptyList) == [false, false, false, false])
            #expect(rows.map(\.isNull) == [true, false, false, false])

            let matching = try await NullableRowModel.query().filter(NullableRowModel.note == "middle").all(on: tx)
            #expect(matching.map(\.note) == ["middle"])
        }
    }

    /// The row `(null.id, NULL)` compares as NULL, never as a match.
    @Test func nullableRowValueInFollowsPostgresThreeValuedLogic() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let null = try await seedNullableRow(on: tx, note: nil)
            let alpha = try await seedNullableRow(on: tx, note: "alpha")
            let beta = try await seedNullableRow(on: tx, note: "beta")

            let alphaNote: String? = "alpha"
            let listed: Expr<Bool?> = SQL.row(NullableRowModel.id, NullableRowModel.note).in([(alpha.id, alphaNote), (null.id, nil)])
            // rust-dbkit decodes the projection into a struct; here it is a tuple.
            let rows: [(Int64, Bool?)] = try await NullableRowModel.query()
                .select(NullableRowModel.id, listed)
                .orderBy(NullableRowModel.id.asc)
                .all(on: tx)
            #expect(rows.map(\.0) == [null.id, alpha.id, beta.id])
            #expect(rows.map(\.1) == [nil, true, false])

            let filtered = try await NullableRowModel.query().filter(listed).all(on: tx)
            #expect(filtered.map(\.id) == [alpha.id])
        }
    }

    @Test func conditionsPreservePostgresThreeValuedLogic() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            for note in [nil, "alpha", "middle", "zulu"] {
                _ = try await seedNullableRow(on: tx, note: note)
            }

            func predicate(_ condition: Condition, _ build: (inout Condition) -> Void) throws -> Expr<Bool?> {
                var condition = condition
                build(&condition)
                return try #require(condition.predicate)
            }
            let singleNullable = try predicate(.all) { $0.add(NullableRowModel.note == "middle") }
            let allWithTrue = try predicate(.all) {
                $0.add(NullableRowModel.note == "middle")
                $0.add(NullableRowModel.id > 0)
            }
            let allWithFalse = try predicate(.all) {
                $0.add(NullableRowModel.note == "middle")
                $0.add(NullableRowModel.id < 0)
            }
            let anyWithFalse = try predicate(.any) {
                $0.add(NullableRowModel.id < 0)
                $0.add(NullableRowModel.note == "middle")
            }
            let anyWithTrue = try predicate(.any) {
                $0.add(NullableRowModel.id > 0)
                $0.add(NullableRowModel.note == "middle")
            }
            let requiredOnly = try predicate(.all) {
                $0.add(NullableRowModel.id > 0)
                $0.add(NullableRowModel.note.isNotNull)
            }
            // rust-dbkit decodes the projection into a struct; here it is a tuple. A predicate is always `Bool?` here,
            // see "A condition's predicate" in `docs/rust-parity.md`, so `required_only` decodes as `Bool?` where
            // rust-dbkit decodes `bool`.
            let rows: [(String?, Bool?, Bool?, Bool?, Bool?, Bool?, Bool?)] = try await NullableRowModel.query()
                .select(NullableRowModel.note, singleNullable, allWithTrue, allWithFalse, anyWithFalse, anyWithTrue, requiredOnly)
                .orderBy(NullableRowModel.id.asc)
                .all(on: tx)

            #expect(rows.map(\.0) == [nil, "alpha", "middle", "zulu"])
            #expect(rows.map(\.1) == [nil, false, true, false])  // single_nullable
            #expect(rows.map(\.2) == [nil, false, true, false])  // all_with_true
            #expect(rows.map(\.3) == [false, false, false, false])  // all_with_false
            #expect(rows.map(\.4) == [nil, false, true, false])  // any_with_false
            #expect(rows.map(\.5) == [true, true, true, true])  // any_with_true
            #expect(rows.map(\.6) == [false, true, true, true])  // required_only

            var condition = Condition.all
            condition.add(NullableRowModel.note == "middle")
            condition.add(NullableRowModel.id > 0)
            let matching = try await NullableRowModel.query().filter(try #require(condition.predicate)).all(on: tx)
            #expect(matching.count == 1)
            #expect(matching.first?.note == "middle")
        }
    }

    /// rust-dbkit's `FromRow` structs are `Decodable` structs here, matched by alias.
    @Test func filteredAggregatesRoundtripWithoutGroupBy() async throws {
        struct FilteredSaleAggregate: Decodable {
            let activeSales: Int64
            let usSales: Int64
            let largeUSSales: Int64
            let missingSales: Int64
            let oldestLargeUSSaleAt: Date?
            let oldestMissingSaleAt: Date?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            let oldestLargeUSSaleAt = isoDate("2024-02-01T12:00:00Z")
            try await SaleModel.insert([
                SaleModel.Insert(region: "us", amount: 40, createdAt: isoDate("2024-02-01T10:00:00Z")),
                SaleModel.Insert(region: "us", amount: 70, createdAt: oldestLargeUSSaleAt),
                SaleModel.Insert(region: "eu", amount: 30, createdAt: isoDate("2024-02-01T14:00:00Z")),
                SaleModel.Insert(region: "apac", amount: 200, createdAt: isoDate("2024-02-02T09:00:00Z")),
                SaleModel.Insert(region: "us", amount: 0, createdAt: isoDate("2024-02-01T08:00:00Z")),
            ])
            .execute(on: tx)

            let largeUSSale: Expr<Bool> = SaleModel.region == "us" && SaleModel.amount >= 50
            let aggregate = try #require(
                try await SaleModel.query()
                    .select(
                        SQL.count(SaleModel.id).as("active_sales"),
                        SQL.count(SaleModel.id).filter(SaleModel.region == "us").as("us_sales"),
                        SQL.count(SaleModel.id).filter(largeUSSale).as("large_us_sales"),
                        SQL.count(SaleModel.id).filter(SaleModel.region == "missing").as("missing_sales"),
                        SQL.min(SaleModel.createdAt).filter(largeUSSale).as("oldest_large_us_sale_at"),
                        SQL.min(SaleModel.createdAt).filter(SaleModel.region == "missing").as("oldest_missing_sale_at")
                    )
                    .filter(SaleModel.amount > 0)
                    .first(as: FilteredSaleAggregate.self, on: tx))

            #expect(aggregate.activeSales == 4)
            #expect(aggregate.usSales == 2)
            #expect(aggregate.largeUSSales == 1)
            #expect(aggregate.missingSales == 0)
            #expect(aggregate.oldestLargeUSSaleAt == oldestLargeUSSaleAt)
            #expect(aggregate.oldestMissingSaleAt == nil)
        }
    }

    /// A `bigint` sum is `numeric`, so `total` is `Decimal?`.
    @Test func filteredAggregatesHandleEmptyAndNullableInputs() async throws {
        struct EmptySumAggregate: Decodable {
            let total: Decimal?
        }
        struct EmptyFilteredSaleAggregate: Decodable {
            let matchingSales: Int64
            let oldestMatchingSaleAt: Date?
        }
        struct FilteredNullableAggregate: Decodable {
            let allRows: Int64
            let nullRows: Int64
            let nonNullNotes: Int64
            let firstNullNote: String?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)

            let emptySum = try #require(
                try await SaleModel.query().select(SQL.sum(SaleModel.amount).as("total")).first(as: EmptySumAggregate.self, on: tx))
            #expect(emptySum.total == nil)

            let empty = try #require(
                try await SaleModel.query()
                    .select(
                        SQL.count(SaleModel.id).filter(SaleModel.region == "us").as("matching_sales"),
                        SQL.min(SaleModel.createdAt).filter(SaleModel.region == "us").as("oldest_matching_sale_at")
                    )
                    .first(as: EmptyFilteredSaleAggregate.self, on: tx))
            #expect(empty.matchingSales == 0)
            #expect(empty.oldestMatchingSaleAt == nil)

            _ = try await seedNullableRow(on: tx, note: nil)
            _ = try await seedNullableRow(on: tx, note: "gamma")
            _ = try await seedNullableRow(on: tx, note: "alpha")

            let nullable = try #require(
                try await NullableRowModel.query()
                    .select(
                        SQL.count(NullableRowModel.id).as("all_rows"),
                        SQL.count(NullableRowModel.id).filter(NullableRowModel.note.isNull).as("null_rows"),
                        SQL.count(NullableRowModel.note).filter(NullableRowModel.id > 0).as("non_null_notes"),
                        SQL.min(NullableRowModel.note).filter(NullableRowModel.note.isNull).as("first_null_note")
                    )
                    .first(as: FilteredNullableAggregate.self, on: tx))
            #expect(nullable.allRows == 3)
            #expect(nullable.nullRows == 1)
            #expect(nullable.nonNullNotes == 2)
            #expect(nullable.firstNullNote == nil)
        }
    }

    /// A `bigint` sum is `numeric`, so `total` is `Decimal?`. rust-dbkit decodes the grouped minimums and maximums as
    /// required values, which these rows always have, and so do these structs.
    @Test func aggregationAndGroupByRoundtrip() async throws {
        struct RegionAggregate: Decodable {
            let region: String
            let total: Decimal?
            let count: Int64
        }
        struct BucketAggregate: Decodable {
            let bucket: Date
            let total: Decimal?
        }
        struct SaleExtremaAggregate: Decodable {
            let region: String
            let firstSaleAt: Date
            let lastSaleAt: Date
            let minAmount: Int64
            let maxAmount: Int64
        }
        struct EmptySaleExtremaAggregate: Decodable {
            let firstSaleAt: Date?
            let lastSaleAt: Date?
            let minAmount: Int64?
            let maxAmount: Int64?
        }
        struct UserTodoAggregate: Decodable {
            let name: String
            let todoCount: Int64
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            let inserted = try await SaleModel.insert([
                SaleModel.Insert(region: "us", amount: 40, createdAt: isoDate("2024-02-01T10:00:00Z")),
                SaleModel.Insert(region: "us", amount: 70, createdAt: isoDate("2024-02-01T12:00:00Z")),
                SaleModel.Insert(region: "eu", amount: 30, createdAt: isoDate("2024-02-01T14:00:00Z")),
                SaleModel.Insert(region: "apac", amount: 200, createdAt: isoDate("2024-02-02T09:00:00Z")),
            ])
            .execute(on: tx)
            #expect(inserted == 4)

            let amountBetween = try await SaleModel.query().filter(SaleModel.amount.between(40, 70)).orderBy(SaleModel.amount.asc).all(
                on: tx)
            #expect(amountBetween.map(\.amount) == [40, 70])

            let day1Sales = try await SaleModel.query()
                .filter(SaleModel.createdAt.between(isoDate("2024-02-01T00:00:00Z"), isoDate("2024-02-01T23:59:59Z")))
                .all(on: tx)
            #expect(day1Sales.count == 3)

            let regionRows = try await SaleModel.query()
                .select(SaleModel.region.as("region"), SQL.sum(SaleModel.amount).as("total"), SQL.count(SaleModel.id).as("count"))
                .groupBy(SaleModel.region)
                .orderBy(SaleModel.region.asc)
                .having(SQL.sum(SaleModel.amount) > 100)
                .all(as: RegionAggregate.self, on: tx)
            #expect(regionRows.map(\.region) == ["apac", "us"])
            #expect(regionRows.map(\.total) == [200, 110])
            #expect(regionRows.map(\.count) == [1, 2])

            let bucketRows = try await SaleModel.query()
                .select(SQL.dateTrunc(.day, SaleModel.createdAt).as("bucket"), SQL.sum(SaleModel.amount).as("total"))
                .groupBy(SQL.dateTrunc(.day, SaleModel.createdAt))
                .all(as: BucketAggregate.self, on: tx)
                .sorted { $0.bucket < $1.bucket }
            #expect(bucketRows.map(\.bucket) == [isoDate("2024-02-01T00:00:00Z"), isoDate("2024-02-02T00:00:00Z")])
            #expect(bucketRows.map(\.total) == [140, 200])

            let orderedBuckets = try await SaleModel.query()
                .select(SQL.dateTrunc(.day, SaleModel.createdAt).as("bucket"), SQL.sum(SaleModel.amount).as("total"))
                .groupBy(SQL.dateTrunc(.day, SaleModel.createdAt))
                .orderBy(SQL.dateTrunc(.day, SaleModel.createdAt).desc)
                .all(as: BucketAggregate.self, on: tx)
            #expect(orderedBuckets.map(\.bucket) == [isoDate("2024-02-02T00:00:00Z"), isoDate("2024-02-01T00:00:00Z")])
            #expect(orderedBuckets.map(\.total) == [200, 140])

            // rust-dbkit orders by the select alias `total`, which is planned (#2); this orders by the aggregate itself.
            let orderedRegions = try await SaleModel.query()
                .select(SaleModel.region.as("region"), SQL.sum(SaleModel.amount).as("total"), SQL.count(SaleModel.id).as("count"))
                .groupBy(SaleModel.region)
                .orderBy(SQL.sum(SaleModel.amount).desc)
                .all(as: RegionAggregate.self, on: tx)
            #expect(orderedRegions.map(\.region) == ["apac", "us", "eu"])
            #expect(orderedRegions.map(\.total) == [200, 110, 30])

            let extremaRows = try await SaleModel.query()
                .select(
                    SaleModel.region.as("region"),
                    SQL.min(SaleModel.createdAt).as("first_sale_at"),
                    SQL.max(SaleModel.createdAt).as("last_sale_at"),
                    SQL.min(SaleModel.amount).as("min_amount"),
                    SQL.max(SaleModel.amount).as("max_amount")
                )
                .groupBy(SaleModel.region)
                .orderBy(SaleModel.region.asc)
                .all(as: SaleExtremaAggregate.self, on: tx)
            try #require(extremaRows.count == 3)
            #expect(extremaRows[0].region == "apac")
            #expect(extremaRows[0].firstSaleAt == isoDate("2024-02-02T09:00:00Z"))
            #expect(extremaRows[0].lastSaleAt == isoDate("2024-02-02T09:00:00Z"))
            #expect(extremaRows[0].minAmount == 200)
            #expect(extremaRows[0].maxAmount == 200)
            #expect(extremaRows[2].region == "us")
            #expect(extremaRows[2].firstSaleAt == isoDate("2024-02-01T10:00:00Z"))
            #expect(extremaRows[2].lastSaleAt == isoDate("2024-02-01T12:00:00Z"))
            #expect(extremaRows[2].minAmount == 40)
            #expect(extremaRows[2].maxAmount == 70)

            let emptyExtrema = try #require(
                try await SaleModel.query()
                    .select(
                        SQL.min(SaleModel.createdAt).as("first_sale_at"),
                        SQL.max(SaleModel.createdAt).as("last_sale_at"),
                        SQL.min(SaleModel.amount).as("min_amount"),
                        SQL.max(SaleModel.amount).as("max_amount")
                    )
                    .filter(SaleModel.region == "missing")
                    .first(as: EmptySaleExtremaAggregate.self, on: tx))
            #expect(emptyExtrema.firstSaleAt == nil)
            #expect(emptyExtrema.lastSaleAt == nil)
            #expect(emptyExtrema.minAmount == nil)
            #expect(emptyExtrema.maxAmount == nil)

            // `join(_:)` belongs to model queries, so it comes before `select`, where rust-dbkit joins after `select_only`.
            let user = try await seedUser(on: tx, name: "AggUser", email: "agg@db.com")
            _ = try await seedTodo(on: tx, userID: user.id, title: "Alpha")
            _ = try await seedTodo(on: tx, userID: user.id, title: "Beta")
            let joinedRows = try await UserModel.query()
                .join(\.todos)
                .select(UserModel.name.as("name"), SQL.count(TodoModel.id).as("todo_count"))
                .groupBy(UserModel.name)
                .orderBy(UserModel.name.desc)
                .all(as: UserTodoAggregate.self, on: tx)
            #expect(joinedRows.count == 1)
            #expect(joinedRows.first?.name == "AggUser")
            #expect(joinedRows.first?.todoCount == 2)
        }
    }

    @Test func minMaxNullableTextRoundtrip() async throws {
        struct NullableNoteExtremaAggregate: Decodable {
            let minNote: String?
            let maxNote: String?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedNullableRow(on: tx, note: nil)
            _ = try await seedNullableRow(on: tx, note: "gamma")
            _ = try await seedNullableRow(on: tx, note: "alpha")

            let extrema = try #require(
                try await NullableRowModel.query()
                    .select(SQL.min(NullableRowModel.note).as("min_note"), SQL.max(NullableRowModel.note).as("max_note"))
                    .first(as: NullableNoteExtremaAggregate.self, on: tx))
            #expect(extrema.minNote == "alpha")
            #expect(extrema.maxNote == "gamma")

            let allNullExtrema = try #require(
                try await NullableRowModel.query()
                    .select(SQL.min(NullableRowModel.note).as("min_note"), SQL.max(NullableRowModel.note).as("max_note"))
                    .filter(NullableRowModel.note.isNull)
                    .first(as: NullableNoteExtremaAggregate.self, on: tx))
            #expect(allNullExtrema.minNote == nil)
            #expect(allNullExtrema.maxNote == nil)
        }
    }

    /// `DATE_TRUNC` of a `timestamp` column truncates in the session's time zone, so this sets it to UTC.
    @Test func functionExpressionsRoundtrip() async throws {
        try await withRollback { tx in
            try await tx.query("SET LOCAL TIME ZONE 'UTC'")
            try await setupSchema(on: tx)
            let row1 = try await seedFuncRow(
                on: tx, email: "alpha@ex.com", backupEmail: nil, region: "us", startsAt: isoDate("2024-01-02T10:00:00Z"))
            let row2 = try await seedFuncRow(
                on: tx, email: nil, backupEmail: "beta@ex.com", region: "eu", startsAt: isoDate("2024-01-02T12:00:00Z"))
            let row3 = try await seedFuncRow(on: tx, email: nil, backupEmail: nil, region: "uk", startsAt: isoDate("2024-01-03T09:00:00Z"))
            let row4 = try await seedFuncRow(
                on: tx, email: "gamma@ex.com", backupEmail: "backup@ex.com", region: nil, startsAt: isoDate("2024-01-03T15:00:00Z"))
            let dayStart = isoDate("2024-01-02T00:00:00Z")

            let upperMatch = try await FuncRowModel.query()
                .filter(SQL.upper(SQL.coalesce(FuncRowModel.email, FuncRowModel.backupEmail)) == "BETA@EX.COM")
                .all(on: tx)
            #expect(upperMatch.map(\.id) == [row2.id])

            let fallbackMatch = try await FuncRowModel.query()
                .filter(SQL.coalesce(FuncRowModel.email, "fallback") == "fallback")
                .all(on: tx)
            #expect(fallbackMatch.map(\.id).sorted() == [row2.id, row3.id])

            let nestedMatch = try await FuncRowModel.query()
                .filter(SQL.coalesce(SQL.coalesce(FuncRowModel.email, FuncRowModel.backupEmail), "none") == "none")
                .all(on: tx)
            #expect(nestedMatch.map(\.id) == [row3.id])

            let truncatedMatch = try await FuncRowModel.query()
                .filter(SQL.dateTrunc(.day, FuncRowModel.startsAt) == dayStart)
                .all(on: tx)
            #expect(truncatedMatch.map(\.id).sorted() == [row1.id, row2.id])

            let regionMatch = try await FuncRowModel.query()
                .filter(SQL.upper(SQL.coalesce(FuncRowModel.region, "unknown")) == "UNKNOWN")
                .all(on: tx)
            #expect(regionMatch.map(\.id) == [row4.id])

            let combinedMatch = try await FuncRowModel.query()
                .filter(SQL.upper(SQL.coalesce(FuncRowModel.email, FuncRowModel.backupEmail)) == "ALPHA@EX.COM")
                .filter(SQL.dateTrunc(.day, FuncRowModel.startsAt) == dayStart)
                .all(on: tx)
            #expect(combinedMatch.map(\.id) == [row1.id])

            let greatestFallback = try await FuncRowModel.query()
                .filter(SQL.greatest(FuncRowModel.email, "") == "")
                .all(on: tx)
            #expect(greatestFallback.map(\.id).sorted() == [row2.id, row3.id])

            let leastFallback = try await FuncRowModel.query()
                .filter(SQL.least("zzzz", FuncRowModel.email) == "zzzz")
                .all(on: tx)
            #expect(leastFallback.map(\.id).sorted() == [row2.id, row3.id])

            let bothNull = try await FuncRowModel.query()
                .filter(SQL.greatest(FuncRowModel.email, FuncRowModel.backupEmail).isNull)
                .all(on: tx)
            #expect(bothNull.map(\.id) == [row3.id])
        }
    }

    @Test func trimFilterMatchesTrimmedText() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let exact = try await seedTextSample(on: tx, label: "exact", body: "alpha")
            let padded = try await seedTextSample(on: tx, label: "padded", body: "  alpha  ")
            _ = try await seedTextSample(on: tx, label: "different", body: "beta")
            _ = try await seedTextSample(on: tx, label: "blank", body: "   ")
            _ = try await seedTextSample(on: tx, label: "missing", body: nil)

            let matches = try await TextSampleModel.query().filter(SQL.trim(TextSampleModel.body) == "alpha").all(on: tx)
            #expect(matches.map(\.id).sorted() == [exact.id, padded.id])
        }
    }

    @Test func charLengthOfTrimmedNullableTextFiltersRows() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "short", body: "  abc  ")
            let long = try await seedTextSample(on: tx, label: "long", body: "  abcdef  ")
            let spaced = try await seedTextSample(on: tx, label: "spaced", body: "     abcde     ")
            _ = try await seedTextSample(on: tx, label: "blank", body: "    ")
            _ = try await seedTextSample(on: tx, label: "missing", body: nil)

            let matches = try await TextSampleModel.query()
                .filter(TextSampleModel.body.isNotNull)
                .filter(SQL.charLength(SQL.trim(TextSampleModel.body)) >= 5)
                .all(on: tx)
            #expect(matches.map(\.id).sorted() == [long.id, spaced.id])
        }
    }

    @Test func stringLengthsDistinguishCharactersBytesAndBits() async throws {
        struct StringLengthResult: Decodable, Equatable {
            let label: String
            let characters: Int32?
            let bytes: Int32?
            let bits: Int32?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "ascii", body: "abc")
            _ = try await seedTextSample(on: tx, label: "unicode", body: "é🙂")
            _ = try await seedTextSample(on: tx, label: "empty", body: "")
            _ = try await seedTextSample(on: tx, label: "whitespace", body: " \t")
            _ = try await seedTextSample(on: tx, label: "missing", body: nil)

            let rows = try await TextSampleModel.query()
                .select(
                    TextSampleModel.label.as("label"),
                    SQL.charLength(TextSampleModel.body).as("characters"),
                    SQL.byteLength(TextSampleModel.body).as("bytes"),
                    SQL.bitLength(TextSampleModel.body).as("bits")
                )
                .orderBy(TextSampleModel.id.asc)
                .all(as: StringLengthResult.self, on: tx)
            #expect(
                rows == [
                    StringLengthResult(label: "ascii", characters: 3, bytes: 3, bits: 24),
                    StringLengthResult(label: "unicode", characters: 2, bytes: 6, bits: 48),
                    StringLengthResult(label: "empty", characters: 0, bytes: 0, bits: 0),
                    StringLengthResult(label: "whitespace", characters: 2, bytes: 2, bits: 16),
                    StringLengthResult(label: "missing", characters: nil, bytes: nil, bits: nil),
                ])
        }
    }

    @Test func stringSearchesCoverPostgresqlBoundariesAndNulls() async throws {
        struct StringSearchResult: Decodable, Equatable {
            let needle: String
            let position: Int32?
            let startsWith: Bool?
            let reversePosition: Int32?
            let reverseStartsWith: Bool?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "", body: "abc")
            _ = try await seedTextSample(on: tx, label: "abc", body: "abc")
            _ = try await seedTextSample(on: tx, label: "abcd", body: "abc")
            _ = try await seedTextSample(on: tx, label: "bc", body: "abcabc")
            _ = try await seedTextSample(on: tx, label: "aba", body: "xababa")
            _ = try await seedTextSample(on: tx, label: "A", body: "abc")
            _ = try await seedTextSample(on: tx, label: "é🙂", body: "xé🙂é")
            _ = try await seedTextSample(on: tx, label: "x", body: "abc")
            _ = try await seedTextSample(on: tx, label: "missing", body: nil)

            let rows = try await TextSampleModel.query()
                .select(
                    TextSampleModel.label.as("needle"),
                    SQL.position(TextSampleModel.body, TextSampleModel.label).as("position"),
                    SQL.startsWith(TextSampleModel.body, TextSampleModel.label).as("starts_with"),
                    SQL.position(TextSampleModel.label, TextSampleModel.body).as("reverse_position"),
                    SQL.startsWith(TextSampleModel.label, TextSampleModel.body).as("reverse_starts_with")
                )
                .orderBy(TextSampleModel.id.asc)
                .all(as: StringSearchResult.self, on: tx)
            #expect(
                rows == [
                    StringSearchResult(needle: "", position: 1, startsWith: true, reversePosition: 0, reverseStartsWith: false),
                    StringSearchResult(needle: "abc", position: 1, startsWith: true, reversePosition: 1, reverseStartsWith: true),
                    StringSearchResult(needle: "abcd", position: 0, startsWith: false, reversePosition: 1, reverseStartsWith: true),
                    StringSearchResult(needle: "bc", position: 2, startsWith: false, reversePosition: 0, reverseStartsWith: false),
                    StringSearchResult(needle: "aba", position: 2, startsWith: false, reversePosition: 0, reverseStartsWith: false),
                    StringSearchResult(needle: "A", position: 0, startsWith: false, reversePosition: 0, reverseStartsWith: false),
                    StringSearchResult(needle: "é🙂", position: 2, startsWith: false, reversePosition: 0, reverseStartsWith: false),
                    StringSearchResult(needle: "x", position: 0, startsWith: false, reversePosition: 0, reverseStartsWith: false),
                    StringSearchResult(needle: "missing", position: nil, startsWith: nil, reversePosition: nil, reverseStartsWith: nil),
                ])
        }
    }

    @Test func stringSearchArgumentsRemainBoundValues() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let search = "'%_\\); DROP TABLE text_samples; --"
            let row = try await seedTextSample(on: tx, label: "\(search)suffix", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.position(TextSampleModel.label, search).as("position"),
                        SQL.startsWith(TextSampleModel.label, search).as("starts_with")
                    )
                    .filter(TextSampleModel.id == row.id)
                    .first(on: tx))
            #expect(result.0 == 1)
            #expect(result.1)
        }
    }

    /// "Normalization" here is trimming and case conversion, not Unicode normalization.
    @Test func stringNormalizationPreservesDirectionAndNullability() async throws {
        struct WhitespaceNormalizationResult: Decodable, Equatable {
            let label: String
            let lowered: String?
            let trimmed: String?
            let startTrimmed: String?
            let endTrimmed: String?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "mixed", body: "  MiXeD  ")
            _ = try await seedTextSample(on: tx, label: "lower", body: "already lower")
            _ = try await seedTextSample(on: tx, label: "empty", body: "")
            _ = try await seedTextSample(on: tx, label: "spaces", body: "   ")
            _ = try await seedTextSample(on: tx, label: "missing", body: nil)

            let rows = try await TextSampleModel.query()
                .select(
                    TextSampleModel.label.as("label"),
                    SQL.lower(TextSampleModel.body).as("lowered"),
                    SQL.trim(TextSampleModel.body).as("trimmed"),
                    SQL.trimStart(TextSampleModel.body).as("start_trimmed"),
                    SQL.trimEnd(TextSampleModel.body).as("end_trimmed")
                )
                .orderBy(TextSampleModel.label.asc)
                .all(as: WhitespaceNormalizationResult.self, on: tx)
            #expect(
                rows == [
                    WhitespaceNormalizationResult(label: "empty", lowered: "", trimmed: "", startTrimmed: "", endTrimmed: ""),
                    WhitespaceNormalizationResult(
                        label: "lower", lowered: "already lower", trimmed: "already lower", startTrimmed: "already lower",
                        endTrimmed: "already lower"),
                    WhitespaceNormalizationResult(label: "missing", lowered: nil, trimmed: nil, startTrimmed: nil, endTrimmed: nil),
                    WhitespaceNormalizationResult(
                        label: "mixed", lowered: "  mixed  ", trimmed: "MiXeD", startTrimmed: "MiXeD  ", endTrimmed: "  MiXeD"),
                    WhitespaceNormalizationResult(label: "spaces", lowered: "   ", trimmed: "", startTrimmed: "", endTrimmed: ""),
                ])
        }
    }

    @Test func customTrimUsesACharacterSetAndHandlesEdgeCases() async throws {
        struct CustomTrimResult: Decodable, Equatable {
            let label: String
            let original: String?
            let both: String?
            let start: String?
            let end: String?
            let emptySet: String?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "all", body: "xyyx")
            _ = try await seedTextSample(on: tx, label: "blocked", body: " xalphay ")
            _ = try await seedTextSample(on: tx, label: "empty", body: "")
            _ = try await seedTextSample(on: tx, label: "internal", body: "xyxyalxphayx")
            _ = try await seedTextSample(on: tx, label: "missing", body: nil)
            _ = try await seedTextSample(on: tx, label: "no_match", body: "alpha")

            let rows = try await TextSampleModel.query()
                .select(
                    TextSampleModel.label.as("label"),
                    TextSampleModel.body.as("original"),
                    SQL.trimChars(TextSampleModel.body, "xy").as("both"),
                    SQL.trimStartChars(TextSampleModel.body, "xy").as("start"),
                    SQL.trimEndChars(TextSampleModel.body, "xy").as("end"),
                    SQL.trimChars(TextSampleModel.body, "").as("empty_set")
                )
                .orderBy(TextSampleModel.label.asc)
                .all(as: CustomTrimResult.self, on: tx)
            #expect(
                rows == [
                    CustomTrimResult(label: "all", original: "xyyx", both: "", start: "", end: "", emptySet: "xyyx"),
                    CustomTrimResult(
                        label: "blocked", original: " xalphay ", both: " xalphay ", start: " xalphay ", end: " xalphay ",
                        emptySet: " xalphay "),
                    CustomTrimResult(label: "empty", original: "", both: "", start: "", end: "", emptySet: ""),
                    CustomTrimResult(
                        label: "internal", original: "xyxyalxphayx", both: "alxpha", start: "alxphayx", end: "xyxyalxpha",
                        emptySet: "xyxyalxphayx"),
                    CustomTrimResult(label: "missing", original: nil, both: nil, start: nil, end: nil, emptySet: nil),
                    CustomTrimResult(label: "no_match", original: "alpha", both: "alpha", start: "alpha", end: "alpha", emptySet: "alpha"),
                ])

            let unicode = try await seedTextSample(on: tx, label: "unicode", body: "ééalphéaé")
            let escaped = try await seedTextSample(on: tx, label: "escaped", body: "'\\alpha\\'")

            let unicodeMatch = try #require(
                try await TextSampleModel.query().filter(SQL.trimChars(TextSampleModel.body, "é") == "alphéa").first(on: tx))
            #expect(unicodeMatch.id == unicode.id)

            let escapedMatch = try #require(
                try await TextSampleModel.query()
                    .filter(TextSampleModel.label == "escaped")
                    .filter(SQL.trimChars(TextSampleModel.body, "'\\") == "alpha")
                    .first(on: tx))
            #expect(escapedMatch.id == escaped.id)
        }
    }

    /// A NULL fill or character set makes the result NULL.
    @Test func nullablePaddingFillAndTrimCharacterSetsFollowPostgresSemantics() async throws {
        struct NullableStringControlArgumentResult: Decodable, Equatable {
            let label: String
            let startPadded: String?
            let endPadded: String?
            let bothTrimmed: String?
            let startTrimmed: String?
            let endTrimmed: String?
            let nullableSourceAndFill: String?
            let nullableSourceAndCharacters: String?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "empty", body: "")
            _ = try await seedTextSample(on: tx, label: "missing", body: nil)
            _ = try await seedTextSample(on: tx, label: "present", body: "xy")

            let rows = try await TextSampleModel.query()
                .select(
                    TextSampleModel.label.as("label"),
                    SQL.padStart("ab", 5, TextSampleModel.body).as("start_padded"),
                    SQL.padEnd("ab", 5, TextSampleModel.body).as("end_padded"),
                    SQL.trimChars("xyhelloyx", TextSampleModel.body).as("both_trimmed"),
                    SQL.trimStartChars("xyhelloyx", TextSampleModel.body).as("start_trimmed"),
                    SQL.trimEndChars("xyhelloyx", TextSampleModel.body).as("end_trimmed"),
                    SQL.padStart(TextSampleModel.body, 5, TextSampleModel.body).as("nullable_source_and_fill"),
                    SQL.trimChars(TextSampleModel.body, TextSampleModel.body).as("nullable_source_and_characters")
                )
                .orderBy(TextSampleModel.label.asc)
                .all(as: NullableStringControlArgumentResult.self, on: tx)
            #expect(
                rows == [
                    NullableStringControlArgumentResult(
                        label: "empty", startPadded: "ab", endPadded: "ab", bothTrimmed: "xyhelloyx", startTrimmed: "xyhelloyx",
                        endTrimmed: "xyhelloyx", nullableSourceAndFill: "", nullableSourceAndCharacters: ""),
                    NullableStringControlArgumentResult(
                        label: "missing", startPadded: nil, endPadded: nil, bothTrimmed: nil, startTrimmed: nil, endTrimmed: nil,
                        nullableSourceAndFill: nil, nullableSourceAndCharacters: nil),
                    NullableStringControlArgumentResult(
                        label: "present", startPadded: "xyxab", endPadded: "abxyx", bothTrimmed: "hello", startTrimmed: "helloyx",
                        endTrimmed: "xyhello", nullableSourceAndFill: "xyxxy", nullableSourceAndCharacters: ""),
                ])
        }
    }

    @Test func nestedNormalizedHandleLookupMatchesEquivalentInputs() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let canonical = try await seedTextSample(on: tx, label: "alice", body: nil)
            let spaced = try await seedTextSample(on: tx, label: " Alice ", body: nil)
            let prefixed = try await seedTextSample(on: tx, label: "@Alice", body: nil)
            let revealedSpace = try await seedTextSample(on: tx, label: " @ Alice ", body: nil)
            let repeatedPrefix = try await seedTextSample(on: tx, label: "@@@ALICE", body: nil)
            _ = try await seedTextSample(on: tx, label: "bob", body: nil)

            let handle = "alice"
            let normalized = SQL.lower(SQL.trim(SQL.trimStartChars(SQL.trim(TextSampleModel.label), "@")))
            let matches = try await TextSampleModel.query().filter(normalized == handle).all(on: tx)
            #expect(
                matches.map(\.id).sorted() == [canonical.id, spaced.id, prefixed.id, revealedSpace.id, repeatedPrefix.id].sorted())
        }
    }

    /// A NULL count, start, length or index makes the result NULL.
    @Test func nullableNumericStringArgumentsFollowPostgresNullSemantics() async throws {
        struct NullableNumericStringArgumentResult: Decodable, Equatable {
            let label: String
            let leftValue: String?
            let rightValue: String?
            let substringValue: String?
            let repeatedValue: String?
            let startPadded: String?
            let endPadded: String?
            let replacedValue: String?
            let splitValue: String?
            let nullableSource: String?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "empty", body: "")
            _ = try await seedTextSample(on: tx, label: "missing", body: nil)
            _ = try await seedTextSample(on: tx, label: "normal", body: "xy")

            let count: Expr<Int32?> = SQL.charLength(TextSampleModel.body)
            let position: Expr<Int32?> = count + 1
            let rows = try await TextSampleModel.query()
                .select(
                    TextSampleModel.label.as("label"),
                    SQL.left("abcdef", count).as("left_value"),
                    SQL.right("abcdef", count).as("right_value"),
                    SQL.substring("abcdef", position, count).as("substring_value"),
                    SQL.repeat("ab", count).as("repeated_value"),
                    SQL.padStart("ab", position, "x").as("start_padded"),
                    SQL.padEnd("ab", position, "x").as("end_padded"),
                    SQL.replaceRange("abcdef", "X", position, count).as("replaced_value"),
                    SQL.splitPart("a,b,c", ",", position).as("split_value"),
                    SQL.left(TextSampleModel.body, count).as("nullable_source")
                )
                .orderBy(TextSampleModel.label.asc)
                .all(as: NullableNumericStringArgumentResult.self, on: tx)
            #expect(
                rows == [
                    NullableNumericStringArgumentResult(
                        label: "empty", leftValue: "", rightValue: "", substringValue: "", repeatedValue: "", startPadded: "a",
                        endPadded: "a", replacedValue: "Xabcdef", splitValue: "a", nullableSource: ""),
                    NullableNumericStringArgumentResult(
                        label: "missing", leftValue: nil, rightValue: nil, substringValue: nil, repeatedValue: nil, startPadded: nil,
                        endPadded: nil, replacedValue: nil, splitValue: nil, nullableSource: nil),
                    NullableNumericStringArgumentResult(
                        label: "normal", leftValue: "ab", rightValue: "ef", substringValue: "cd", repeatedValue: "abab",
                        startPadded: "xab", endPadded: "abx", replacedValue: "abXef", splitValue: "c", nullableSource: "xy"),
                ])

            let matching = try await TextSampleModel.query()
                .filter(SQL.left("abcdef", SQL.charLength(TextSampleModel.body)) == "ab")
                .all(on: tx)
            #expect(matching.map(\.label) == ["normal"])
        }
    }

    @Test func stringExtractionAndSizingPreserveCharactersAndNulls() async throws {
        struct ExtractionSizingResult: Decodable, Equatable {
            let label: String
            let leftValue: String?
            let rightValue: String?
            let substringValue: String?
            let repeatedValue: String?
            let startPadded: String?
            let endPadded: String?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "ascii", body: "abcdef")
            _ = try await seedTextSample(on: tx, label: "empty", body: "")
            _ = try await seedTextSample(on: tx, label: "missing", body: nil)
            _ = try await seedTextSample(on: tx, label: "unicode", body: "é🦀界")

            let rows = try await TextSampleModel.query()
                .select(
                    TextSampleModel.label.as("label"),
                    SQL.left(TextSampleModel.body, 2).as("left_value"),
                    SQL.right(TextSampleModel.body, 2).as("right_value"),
                    SQL.substring(TextSampleModel.body, 2, 3).as("substring_value"),
                    SQL.repeat(TextSampleModel.body, 2).as("repeated_value"),
                    SQL.padStart(TextSampleModel.body, 8, "xy").as("start_padded"),
                    SQL.padEnd(TextSampleModel.body, 8, "xy").as("end_padded")
                )
                .orderBy(TextSampleModel.label.asc)
                .all(as: ExtractionSizingResult.self, on: tx)
            #expect(
                rows == [
                    ExtractionSizingResult(
                        label: "ascii", leftValue: "ab", rightValue: "ef", substringValue: "bcd", repeatedValue: "abcdefabcdef",
                        startPadded: "xyabcdef", endPadded: "abcdefxy"),
                    ExtractionSizingResult(
                        label: "empty", leftValue: "", rightValue: "", substringValue: "", repeatedValue: "", startPadded: "xyxyxyxy",
                        endPadded: "xyxyxyxy"),
                    ExtractionSizingResult(
                        label: "missing", leftValue: nil, rightValue: nil, substringValue: nil, repeatedValue: nil, startPadded: nil,
                        endPadded: nil),
                    ExtractionSizingResult(
                        label: "unicode", leftValue: "é🦀", rightValue: "🦀界", substringValue: "🦀界", repeatedValue: "é🦀界é🦀界",
                        startPadded: "xyxyxé🦀界", endPadded: "é🦀界xyxyx"),
                ])
        }
    }

    @Test func stringExtractionAndSizingFollowPostgresBoundarySemantics() async throws {
        struct StringFunctionBoundaryResult: Decodable {
            let leftZero: String
            let leftLong: String
            let leftNegative: String
            let rightZero: String
            let rightLong: String
            let rightNegative: String
            let substringOne: String
            let substringZeroStart: String
            let substringNegativeStart: String
            let substringZeroCount: String
            let substringLongCount: String
            let repeatZero: String
            let repeatOne: String
            let repeatNegative: String
            let padStartShorter: String
            let padStartEqual: String
            let padStartLonger: String
            let padStartSingleFill: String
            let padStartEmptyFill: String
            let padStartNegative: String
            let padEndShorter: String
            let padEndEqual: String
            let padEndLonger: String
            let padEndSingleFill: String
            let padEndEmptyFill: String
            let padEndNegative: String
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "boundary", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.left("abcdef", 0).as("left_zero"),
                        SQL.left("abcdef", 99).as("left_long"),
                        SQL.left("abcdef", -2).as("left_negative"),
                        SQL.right("abcdef", 0).as("right_zero"),
                        SQL.right("abcdef", 99).as("right_long"),
                        SQL.right("abcdef", -2).as("right_negative"),
                        SQL.substring("abcdef", 1, 3).as("substring_one"),
                        SQL.substring("abcdef", 0, 3).as("substring_zero_start"),
                        SQL.substring("abcdef", -2, 5).as("substring_negative_start"),
                        SQL.substring("abcdef", 2, 0).as("substring_zero_count"),
                        SQL.substring("abcdef", 2, 99).as("substring_long_count"),
                        SQL.repeat("ab", 0).as("repeat_zero"),
                        SQL.repeat("ab", 1).as("repeat_one"),
                        SQL.repeat("ab", -2).as("repeat_negative"),
                        SQL.padStart("abcdef", 4, "xy").as("pad_start_shorter"),
                        SQL.padStart("abcdef", 6, "xy").as("pad_start_equal"),
                        SQL.padStart("abcdef", 9, "xy").as("pad_start_longer"),
                        SQL.padStart("ab", 5, ".").as("pad_start_single_fill"),
                        SQL.padStart("abcdef", 9, "").as("pad_start_empty_fill"),
                        SQL.padStart("abcdef", -1, "xy").as("pad_start_negative"),
                        SQL.padEnd("abcdef", 4, "xy").as("pad_end_shorter"),
                        SQL.padEnd("abcdef", 6, "xy").as("pad_end_equal"),
                        SQL.padEnd("abcdef", 9, "xy").as("pad_end_longer"),
                        SQL.padEnd("ab", 5, ".").as("pad_end_single_fill"),
                        SQL.padEnd("abcdef", 9, "").as("pad_end_empty_fill"),
                        SQL.padEnd("abcdef", -1, "xy").as("pad_end_negative")
                    )
                    .first(as: StringFunctionBoundaryResult.self, on: tx))

            #expect(result.leftZero == "")
            #expect(result.leftLong == "abcdef")
            #expect(result.leftNegative == "abcd")
            #expect(result.rightZero == "")
            #expect(result.rightLong == "abcdef")
            #expect(result.rightNegative == "cdef")
            #expect(result.substringOne == "abc")
            #expect(result.substringZeroStart == "ab")
            #expect(result.substringNegativeStart == "ab")
            #expect(result.substringZeroCount == "")
            #expect(result.substringLongCount == "bcdef")
            #expect(result.repeatZero == "")
            #expect(result.repeatOne == "ab")
            #expect(result.repeatNegative == "")
            #expect(result.padStartShorter == "abcd")
            #expect(result.padStartEqual == "abcdef")
            #expect(result.padStartLonger == "xyxabcdef")
            #expect(result.padStartSingleFill == "...ab")
            #expect(result.padStartEmptyFill == "abcdef")
            #expect(result.padStartNegative == "")
            #expect(result.padEndShorter == "abcd")
            #expect(result.padEndEqual == "abcdef")
            #expect(result.padEndLonger == "abcdefxyx")
            #expect(result.padEndSingleFill == "ab...")
            #expect(result.padEndEmptyFill == "abcdef")
            #expect(result.padEndNegative == "")
        }
    }

    /// "Normalization" here is trimming and case conversion, not Unicode normalization.
    @Test func stringExtractionAndSizingComposeWithNormalizationAndExpressionCounts() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "xxx", body: "  AbCd  ")

            let normalized = SQL.lower(SQL.trim(TextSampleModel.body))
            let count = SQL.charLength(TextSampleModel.label)
            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.left(SQL.trim(TextSampleModel.body), count).as("extracted"),
                        SQL.padEnd(SQL.substring(normalized, 2, count), 8, SQL.lower("Q%_\\'")).as("padded"),
                        SQL.repeat(SQL.right(normalized, count), 2).as("repeated")
                    )
                    .filter(SQL.left(normalized, 2) == "ab")
                    .orderBy(SQL.padStart(TextSampleModel.label, 5, "0").asc)
                    .first(on: tx))

            #expect(result.0 == "AbC")
            #expect(result.1 == "bcdq%_\\'")
            #expect(result.2 == "bcdbcd")
        }
    }

    @Test func substringRejectsNegativeCount() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "negative", body: "abcdef")

            let error = try await #require(throws: PSQLError.self) {
                try await TextSampleModel.query().select(SQL.substring(TextSampleModel.body, 1, -1).as("value")).all(on: tx)
            }
            #expect(error.serverInfo?[.message] == "negative substring length not allowed")
        }
    }

    @Test func titleCaseAndReverseFollowPostgresqlCharacterSemantics() async throws {
        struct TextCaseAndReverseResult: Decodable {
            let titleWords: String
            let titleAlreadyCased: String
            let titlePunctuation: String
            let titleDigits: String
            let titleWhitespace: String
            let titleUnicodeSeparator: String
            let titleEmpty: String
            let reverseASCII: String
            let reverseUnicode: String
            let reverseCombiningSequence: String
            let reverseEmpty: String
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "character-semantics", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.titleCase("hELLO wORLD").as("title_words"),
                        SQL.titleCase("Already Cased").as("title_already_cased"),
                        SQL.titleCase("one-two_three.four").as("title_punctuation"),
                        SQL.titleCase("abc123 42FOO").as("title_digits"),
                        SQL.titleCase("\theLLo  wORLD\n").as("title_whitespace"),
                        SQL.titleCase("hello—WORLD").as("title_unicode_separator"),
                        SQL.titleCase("").as("title_empty"),
                        SQL.reverse("abcde").as("reverse_ascii"),
                        SQL.reverse("é🦀界").as("reverse_unicode"),
                        SQL.reverse("a\u{301}b").as("reverse_combining_sequence"),
                        SQL.reverse("").as("reverse_empty")
                    )
                    .first(as: TextCaseAndReverseResult.self, on: tx))

            #expect(result.titleWords == "Hello World")
            #expect(result.titleAlreadyCased == "Already Cased")
            #expect(result.titlePunctuation == "One-Two_Three.Four")
            #expect(result.titleDigits == "Abc123 42foo")
            #expect(result.titleWhitespace == "\tHello  World\n")
            #expect(result.titleUnicodeSeparator == "Hello—World")
            #expect(result.titleEmpty == "")
            #expect(result.reverseASCII == "edcba")
            #expect(result.reverseUnicode == "界🦀é")
            #expect(result.reverseCombiningSequence == "b\u{301}a")
            #expect(result.reverseEmpty == "")
        }
    }

    @Test func replaceAndTranslateCoverExactMappingSemantics() async throws {
        struct ReplaceAndTranslateResult: Decodable {
            let replaceAll: String
            let replaceNonOverlapping: String
            let replaceAbsent: String
            let replaceEmptySource: String
            let replaceEmptyFrom: String
            let replaceEmptyTo: String
            let replaceCaseSensitive: String
            let replaceUnicode: String
            let translatePositional: String
            let translateDeletion: String
            let translateExtraTo: String
            let translateRepeatedSource: String
            let translateUnicode: String
            let translateEmptyFrom: String
            let translateEmptyTo: String
            let translateCaseSensitive: String
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "mapping-semantics", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.replace("abcabc", "bc", "X").as("replace_all"),
                        SQL.replace("aaaaa", "aa", "b").as("replace_non_overlapping"),
                        SQL.replace("abc", "z", "X").as("replace_absent"),
                        SQL.replace("", "a", "X").as("replace_empty_source"),
                        SQL.replace("abc", "", "X").as("replace_empty_from"),
                        SQL.replace("banana", "an", "").as("replace_empty_to"),
                        SQL.replace("AaA", "a", "x").as("replace_case_sensitive"),
                        SQL.replace("é🦀é", "é", "界").as("replace_unicode"),
                        SQL.translateChars("12345", "143", "ax").as("translate_positional"),
                        SQL.translateChars("12345", "143", "a").as("translate_deletion"),
                        SQL.translateChars("abc", "ab", "XYZ").as("translate_extra_to"),
                        SQL.translateChars("banana", "an", "12").as("translate_repeated_source"),
                        SQL.translateChars("é🦀界é", "é界", "ab").as("translate_unicode"),
                        SQL.translateChars("abc", "", "xyz").as("translate_empty_from"),
                        SQL.translateChars("banana", "an", "").as("translate_empty_to"),
                        SQL.translateChars("Aa", "a", "x").as("translate_case_sensitive")
                    )
                    .first(as: ReplaceAndTranslateResult.self, on: tx))

            #expect(result.replaceAll == "aXaX")
            #expect(result.replaceNonOverlapping == "bba")
            #expect(result.replaceAbsent == "abc")
            #expect(result.replaceEmptySource == "")
            #expect(result.replaceEmptyFrom == "abc")
            #expect(result.replaceEmptyTo == "ba")
            #expect(result.replaceCaseSensitive == "AxA")
            #expect(result.replaceUnicode == "界🦀界")
            #expect(result.translatePositional == "a2x5")
            #expect(result.translateDeletion == "a25")
            #expect(result.translateExtraTo == "XYc")
            #expect(result.translateRepeatedSource == "b12121")
            #expect(result.translateUnicode == "a🦀ba")
            #expect(result.translateEmptyFrom == "abc")
            #expect(result.translateEmptyTo == "b")
            #expect(result.translateCaseSensitive == "Ax")
        }
    }

    @Test func textTransformationsPropagateNullFromEveryStringArgument() async throws {
        struct NullableTextTransformationResult: Decodable, Equatable {
            let titleCase: String?
            let reverse: String?
            let replaceInput: String?
            let replaceFrom: String?
            let replaceTo: String?
            let rangeInput: String?
            let rangeReplacement: String?
            let translateInput: String?
            let translateFrom: String?
            let translateTo: String?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row = try await seedTextSample(on: tx, label: "nullable", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.titleCase(TextSampleModel.body).as("title_case"),
                        SQL.reverse(TextSampleModel.body).as("reverse"),
                        SQL.replace(TextSampleModel.body, "a", "b").as("replace_input"),
                        SQL.replace(TextSampleModel.label, TextSampleModel.body, "b").as("replace_from"),
                        SQL.replace(TextSampleModel.label, "a", TextSampleModel.body).as("replace_to"),
                        SQL.replaceRange(TextSampleModel.body, "x", 1, 1).as("range_input"),
                        SQL.replaceRange(TextSampleModel.label, TextSampleModel.body, 1, 1).as("range_replacement"),
                        SQL.translateChars(TextSampleModel.body, "a", "b").as("translate_input"),
                        SQL.translateChars(TextSampleModel.label, TextSampleModel.body, "b").as("translate_from"),
                        SQL.translateChars(TextSampleModel.label, "a", TextSampleModel.body).as("translate_to")
                    )
                    .filter(TextSampleModel.id == row.id)
                    .first(as: NullableTextTransformationResult.self, on: tx))
            #expect(
                result
                    == NullableTextTransformationResult(
                        titleCase: nil, reverse: nil, replaceInput: nil, replaceFrom: nil, replaceTo: nil, rangeInput: nil,
                        rangeReplacement: nil, translateInput: nil, translateFrom: nil, translateTo: nil))
        }
    }

    @Test func nestedTextTransformationsFilterRealPostgresqlRows() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "matched", body: "  hELLO-old  ")
            _ = try await seedTextSample(on: tx, label: "other", body: "  HELLO-current  ")
            _ = try await seedTextSample(on: tx, label: "missing", body: nil)

            let transformed: Expr<String?> = SQL.reverse(
                SQL.translateChars(
                    SQL.replace(
                        SQL.titleCase(SQL.lower(SQL.trim(TextSampleModel.body))),
                        SQL.titleCase("OLD"),
                        SQL.reverse("wen")
                    ),
                    SQL.lower("E"),
                    SQL.upper("x")
                ))
            let result = try #require(
                try await TextSampleModel.query()
                    .select(TextSampleModel.label.as("label"), transformed.as("transformed"))
                    .filter(transformed == "wXn-ollXH")
                    .first(on: tx))
            #expect(result.0 == "matched")
            #expect(result.1 == "wXn-ollXH")
        }
    }

    @Test func replaceRangeFollowsPostgresqlOverlayBoundaries() async throws {
        struct ReplaceRangeBoundaryResult: Decodable {
            let shorter: String
            let equal: String
            let longer: String
            let startOne: String
            let startBeyondEnd: String
            let zeroCount: String
            let negativeCount: String
            let oversizedCount: String
            let emptySource: String
            let emptyReplacement: String
            let unicode: String
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "overlay-boundaries", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.replaceRange("abcdef", "X", 3, 2).as("shorter"),
                        SQL.replaceRange("abcdef", "XY", 3, 2).as("equal"),
                        SQL.replaceRange("abcdef", "WXYZ", 3, 2).as("longer"),
                        SQL.replaceRange("abcdef", "X", 1, 2).as("start_one"),
                        SQL.replaceRange("abcdef", "X", 8, 2).as("start_beyond_end"),
                        SQL.replaceRange("abcdef", "X", 3, 0).as("zero_count"),
                        SQL.replaceRange("abcdef", "X", 3, -1).as("negative_count"),
                        SQL.replaceRange("abcdef", "X", 3, 99).as("oversized_count"),
                        SQL.replaceRange("", "X", 1, 0).as("empty_source"),
                        SQL.replaceRange("abcdef", "", 3, 2).as("empty_replacement"),
                        SQL.replaceRange("a🦀界b", "é", 2, 2).as("unicode")
                    )
                    .first(as: ReplaceRangeBoundaryResult.self, on: tx))

            #expect(result.shorter == "abXef")
            #expect(result.equal == "abXYef")
            #expect(result.longer == "abWXYZef")
            #expect(result.startOne == "Xcdef")
            #expect(result.startBeyondEnd == "abcdefX")
            #expect(result.zeroCount == "abXcdef")
            #expect(result.negativeCount == "abXbcdef")
            #expect(result.oversizedCount == "abX")
            #expect(result.emptySource == "X")
            #expect(result.emptyReplacement == "abef")
            #expect(result.unicode == "aéb")
        }
    }

    @Test func textTransformationMetacharactersRemainBoundValues() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "bind-safety", body: nil)

            let unsafeText = "'%_\\[]().*+"
            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.replace(unsafeText, "%_\\", "safe").as("replaced"),
                        SQL.replaceRange(unsafeText, "safe", 2, 3).as("ranged"),
                        SQL.translateChars(unsafeText, "'\\", "QB").as("translated")
                    )
                    .first(on: tx))
            #expect(result.0 == "'safe[]().*+")
            #expect(result.1 == "'safe[]().*+")
            #expect(result.2 == "Q%_B[]().*+")
        }
    }

    /// PostgreSQL reports a start below 1 as a negative substring length.
    @Test func replaceRangeRejectsZeroStart() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "invalid-overlay-start", body: nil)

            let error = try await #require(throws: PSQLError.self) {
                try await TextSampleModel.query().select(SQL.replaceRange("abcdef", "X", 0, 2).as("value")).all(on: tx)
            }
            #expect(error.serverInfo?[.message] == "negative substring length not allowed")
        }
    }

    /// rust-dbkit passes the values as an array; here they are arguments.
    @Test func concatFunctionsFollowPostgresNullEmptyAndUnicodeSemantics() async throws {
        struct StringCompositionResult: Decodable, Equatable {
            let joined: String
            let separated: String
            let emptySeparator: String
            let nullableSeparator: String?
            let single: String
            let singleSeparated: String
            let noValues: String
            let noSeparatedValues: String
            let noValuesNullableSeparator: String?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            let rows: [(String?, String?, String?)] = [("é", nil, "界"), (nil, nil, nil), ("", "", ""), ("A", "B", nil)]
            for (email, backupEmail, region) in rows {
                _ = try await seedFuncRow(
                    on: tx, email: email, backupEmail: backupEmail, region: region, startsAt: Date(timeIntervalSince1970: 0))
            }

            let results = try await FuncRowModel.query()
                .select(
                    SQL.concat(FuncRowModel.email, FuncRowModel.backupEmail, FuncRowModel.region).as("joined"),
                    SQL.concatWithSeparator("|", FuncRowModel.email, FuncRowModel.backupEmail, FuncRowModel.region).as("separated"),
                    SQL.concatWithSeparator("", FuncRowModel.email, FuncRowModel.backupEmail, FuncRowModel.region).as("empty_separator"),
                    SQL.concatWithSeparator(FuncRowModel.region, FuncRowModel.email, FuncRowModel.backupEmail).as("nullable_separator"),
                    SQL.concat(FuncRowModel.email).as("single"),
                    SQL.concatWithSeparator("|", FuncRowModel.email).as("single_separated"),
                    SQL.concat().as("no_values"),
                    SQL.concatWithSeparator("|").as("no_separated_values"),
                    SQL.concatWithSeparator(FuncRowModel.region).as("no_values_nullable_separator")
                )
                .orderBy(FuncRowModel.id.asc)
                .all(as: StringCompositionResult.self, on: tx)
            #expect(
                results == [
                    StringCompositionResult(
                        joined: "é界", separated: "é|界", emptySeparator: "é界", nullableSeparator: "é", single: "é",
                        singleSeparated: "é", noValues: "", noSeparatedValues: "", noValuesNullableSeparator: ""),
                    StringCompositionResult(
                        joined: "", separated: "", emptySeparator: "", nullableSeparator: nil, single: "", singleSeparated: "",
                        noValues: "", noSeparatedValues: "", noValuesNullableSeparator: nil),
                    StringCompositionResult(
                        joined: "", separated: "||", emptySeparator: "", nullableSeparator: "", single: "", singleSeparated: "",
                        noValues: "", noSeparatedValues: "", noValuesNullableSeparator: ""),
                    StringCompositionResult(
                        joined: "AB", separated: "A|B", emptySeparator: "AB", nullableSeparator: nil, single: "A",
                        singleSeparated: "A", noValues: "", noSeparatedValues: "", noValuesNullableSeparator: nil),
                ])
        }
    }

    /// rust-dbkit's macros take a bracketed list; here the values are arguments. Swift has no counterpart for its
    /// dynamically built lists, the `dynamic_joined` and `dynamic_separated` columns.
    @Test func concatMacrosSupportRequiredNullableDynamicAndEmptyValues() async throws {
        struct MixedModelColumnConcatResult: Decodable, Equatable {
            let joined: String
            let separated: String
            let nullableSeparator: String?
            let emptyJoined: String
            let emptySeparated: String
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "required", body: "optional")
            _ = try await seedTextSample(on: tx, label: "required", body: nil)

            let rows = try await TextSampleModel.query()
                .select(
                    SQL.concat(TextSampleModel.label, TextSampleModel.body).as("joined"),
                    SQL.concatWithSeparator("|", TextSampleModel.label, TextSampleModel.body).as("separated"),
                    SQL.concatWithSeparator(TextSampleModel.body, TextSampleModel.label, "suffix").as("nullable_separator"),
                    SQL.concat().as("empty_joined"),
                    SQL.concatWithSeparator("|").as("empty_separated")
                )
                .orderBy(TextSampleModel.id.asc)
                .all(as: MixedModelColumnConcatResult.self, on: tx)
            #expect(
                rows == [
                    MixedModelColumnConcatResult(
                        joined: "requiredoptional", separated: "required|optional", nullableSeparator: "requiredoptionalsuffix",
                        emptyJoined: "", emptySeparated: ""),
                    MixedModelColumnConcatResult(
                        joined: "required", separated: "required", nullableSeparator: nil, emptyJoined: "", emptySeparated: ""),
                ])
        }
    }

    /// A NULL delimiter splits into characters, so only the source makes the result NULL.
    @Test func splitFollowsPostgresArrayAndNullSemantics() async throws {
        struct SplitResult: Decodable {
            let normal: [String]
            let repeated: [String]
            let absent: [String]
            let emptySource: [String]
            let emptyDelimiter: [String]
            let unicode: [String]
            let nullDelimiter: [String]
            let nullSource: [String]?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "boundary", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.split("alpha::beta::gamma", "::").as("normal"),
                        SQL.split("a::::c::", "::").as("repeated"),
                        SQL.split("abc", ",").as("absent"),
                        SQL.split("", ",").as("empty_source"),
                        SQL.split("abc", "").as("empty_delimiter"),
                        SQL.split("é🙂界🙂ß", "🙂").as("unicode"),
                        SQL.split("é🙂", TextSampleModel.body).as("null_delimiter"),
                        SQL.split(TextSampleModel.body, ",").as("null_source")
                    )
                    .first(as: SplitResult.self, on: tx))

            #expect(result.normal == ["alpha", "beta", "gamma"])
            #expect(result.repeated == ["a", "", "c", ""])
            #expect(result.absent == ["abc"])
            #expect(result.emptySource.isEmpty)
            #expect(result.emptyDelimiter == ["abc"])
            #expect(result.unicode == ["é", "界", "ß"])
            #expect(result.nullDelimiter == ["é", "🙂"])
            #expect(result.nullSource == nil)
        }
    }

    @Test func splitPartFollowsPostgresIndexFieldAndNullSemantics() async throws {
        struct SplitPartResult: Decodable {
            let normal: String
            let negative: String
            let outOfRange: String
            let emptyDelimiterFirst: String
            let emptyDelimiterSecond: String
            let repeatedDelimiter: String
            let leadingEmpty: String
            let trailingEmpty: String
            let unicode: String
            let expressionIndex: String
            let nullSource: String?
            let nullDelimiter: String?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "boundary", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.splitPart("alpha::beta::gamma", "::", 2).as("normal"),
                        SQL.splitPart("a,b,c,d", ",", -2).as("negative"),
                        SQL.splitPart("a,b", ",", 3).as("out_of_range"),
                        SQL.splitPart("abc", "", 1).as("empty_delimiter_first"),
                        SQL.splitPart("abc", "", 2).as("empty_delimiter_second"),
                        SQL.splitPart("a,,c", ",", 2).as("repeated_delimiter"),
                        SQL.splitPart(",a", ",", 1).as("leading_empty"),
                        SQL.splitPart("a,", ",", -1).as("trailing_empty"),
                        SQL.splitPart("é🙂界🙂ß", "🙂", -2).as("unicode"),
                        SQL.splitPart("é🙂界", "🙂", SQL.charLength("x")).as("expression_index"),
                        SQL.splitPart(TextSampleModel.body, ",", 1).as("null_source"),
                        SQL.splitPart("abc", TextSampleModel.body, 1).as("null_delimiter")
                    )
                    .first(as: SplitPartResult.self, on: tx))

            #expect(result.normal == "beta")
            #expect(result.negative == "c")
            #expect(result.outOfRange == "")
            #expect(result.emptyDelimiterFirst == "abc")
            #expect(result.emptyDelimiterSecond == "")
            #expect(result.repeatedDelimiter == "")
            #expect(result.leadingEmpty == "")
            #expect(result.trailingEmpty == "")
            #expect(result.unicode == "界")
            #expect(result.expressionIndex == "é")
            #expect(result.nullSource == nil)
            #expect(result.nullDelimiter == nil)
        }
    }

    @Test func splitPartRejectsZeroIndex() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "zero", body: nil)

            let error = try await #require(throws: PSQLError.self) {
                try await TextSampleModel.query().select(SQL.splitPart(TextSampleModel.label, ",", 0).as("value")).all(on: tx)
            }
            #expect(error.serverInfo?[.message] == "field position must not be zero")
        }
    }

    @Test func compositionAndSplitArgumentsRemainBoundValues() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "bound", body: nil)

            let unsafeText = "'%_\\.*+?[](){}^$|"
            let source = "left\(unsafeText)right"
            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.concat(unsafeText, SQL.lower("TAIL")).as("joined"),
                        SQL.concatWithSeparator(unsafeText, "left", "right").as("separated"),
                        SQL.split(source, unsafeText).as("parts"),
                        SQL.splitPart(source, unsafeText, 2).as("second_part")
                    )
                    .first(on: tx))
            #expect(result.0 == "\(unsafeText)tail")
            #expect(result.1 == "left\(unsafeText)right")
            #expect(result.2 == ["left", "right"])
            #expect(result.3 == "right")
        }
    }

    @Test func regexReplaceFollowsPostgreSQLMatchReplacementAndFlagSemantics() async throws {
        struct RegexReplaceBoundaryResult: Decodable {
            let firstMatch: String
            let global: String
            let noMatch: String
            let emptySource: String
            let emptyPatternFirst: String
            let emptyPatternGlobal: String
            let emptyReplacement: String
            let captureGroups: String
            let wholeMatch: String
            let literalBackslash: String
            let literalDollarQuote: String
            let caseSensitive: String
            let caseInsensitive: String
            let zeroWidth: String
            let unicode: String
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "regex-replace", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.regexReplace("abcabc", "a.", "X", []).as("first_match"),
                        SQL.regexReplace("abcabc", "a.", "X", .global).as("global"),
                        SQL.regexReplace("abc", "z+", "X", []).as("no_match"),
                        SQL.regexReplace("", "a", "X", []).as("empty_source"),
                        SQL.regexReplace("abc", "", "X", []).as("empty_pattern_first"),
                        SQL.regexReplace("abc", "", "X", .global).as("empty_pattern_global"),
                        SQL.regexReplace("a1b22c", #"\d+"#, "", .global).as("empty_replacement"),
                        SQL.regexReplace("Ada Lovelace", "([A-Za-z]+) ([A-Za-z]+)", #"\2, \1"#, []).as("capture_groups"),
                        SQL.regexReplace("abc", "b", #"[\&]"#, []).as("whole_match"),
                        SQL.regexReplace("abc", "b", #"\\"#, []).as("literal_backslash"),
                        SQL.regexReplace("abc", "b", "$1'&", []).as("literal_dollar_quote"),
                        SQL.regexReplace("AaA", "a", "x", .global).as("case_sensitive"),
                        SQL.regexReplace("AaA", "a", "x", [.global, .caseInsensitive]).as("case_insensitive"),
                        SQL.regexReplace("ab", "(^|$)", "_", .global).as("zero_width"),
                        SQL.regexReplace("é🙂é", "[é🙂]", "X", .global).as("unicode")
                    )
                    .first(as: RegexReplaceBoundaryResult.self, on: tx))

            #expect(result.firstMatch == "Xcabc")
            #expect(result.global == "XcXc")
            #expect(result.noMatch == "abc")
            #expect(result.emptySource == "")
            #expect(result.emptyPatternFirst == "Xabc")
            #expect(result.emptyPatternGlobal == "XaXbXcX")
            #expect(result.emptyReplacement == "abc")
            #expect(result.captureGroups == "Lovelace, Ada")
            #expect(result.wholeMatch == "a[b]c")
            #expect(result.literalBackslash == "a\\c")
            #expect(result.literalDollarQuote == "a$1'&c")
            #expect(result.caseSensitive == "AxA")
            #expect(result.caseInsensitive == "xxx")
            #expect(result.zeroWidth == "_ab_")
            #expect(result.unicode == "XXX")
        }
    }

    @Test func regexSplitReturnsExactTextArraysAndSuppressesSpecialZeroWidthMatches() async throws {
        struct RegexSplitBoundaryResult: Decodable {
            let normal: [String]
            let repeated: [String]
            let adjacent: [String]
            let edges: [String]
            let noMatch: [String]
            let emptySource: [String]
            let emptyPattern: [String]
            let zeroWidthStar: [String]
            let zeroWidthLookahead: [String]
            let zeroWidthBoundaries: [String]
            let unicode: [String]
            let caseSensitive: [String]
            let caseInsensitive: [String]
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "regex-split", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.regexSplit("one, two;three", "[,;][ ]*", []).as("normal"),
                        SQL.regexSplit("a,,b;;;c", "[,;]+", []).as("repeated"),
                        SQL.regexSplit("a,,b", ",", []).as("adjacent"),
                        SQL.regexSplit(",a,", ",", []).as("edges"),
                        SQL.regexSplit("abc", ",", []).as("no_match"),
                        SQL.regexSplit("", ",", []).as("empty_source"),
                        SQL.regexSplit("abc", "", []).as("empty_pattern"),
                        SQL.regexSplit("the quick", "[ ]*", []).as("zero_width_star"),
                        SQL.regexSplit("abc", "(?=b)", []).as("zero_width_lookahead"),
                        SQL.regexSplit("abc", "(^|$)", []).as("zero_width_boundaries"),
                        SQL.regexSplit("été🙂hiver", "[é🙂]+", []).as("unicode"),
                        SQL.regexSplit("aXbxc", "x", []).as("case_sensitive"),
                        SQL.regexSplit("aXbxc", "x", .caseInsensitive).as("case_insensitive")
                    )
                    .first(as: RegexSplitBoundaryResult.self, on: tx))

            #expect(result.normal == ["one", "two", "three"])
            #expect(result.repeated == ["a", "b", "c"])
            #expect(result.adjacent == ["a", "", "b"])
            #expect(result.edges == ["", "a", ""])
            #expect(result.noMatch == ["abc"])
            #expect(result.emptySource == [""])
            #expect(result.emptyPattern == ["a", "b", "c"])
            #expect(result.zeroWidthStar == ["t", "h", "e", "q", "u", "i", "c", "k"])
            #expect(result.zeroWidthLookahead == ["a", "bc"])
            #expect(result.zeroWidthBoundaries == ["abc"])
            #expect(result.unicode == ["", "t", "hiver"])
            #expect(result.caseSensitive == ["aXb", "c"])
            #expect(result.caseInsensitive == ["a", "b", "c"])
        }
    }

    @Test func regexTransformsPropagateNullFromEveryNullableTextArgument() async throws {
        struct NullableRegexTransformResult: Decodable, Equatable {
            let replaceSource: String?
            let replacePattern: String?
            let replaceReplacement: String?
            let splitSource: [String]?
            let splitPattern: [String]?
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row = try await seedTextSample(on: tx, label: "abc", body: nil)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.regexReplace(TextSampleModel.body, "a", "x", []).as("replace_source"),
                        SQL.regexReplace(TextSampleModel.label, TextSampleModel.body, "x", []).as("replace_pattern"),
                        SQL.regexReplace(TextSampleModel.label, "a", TextSampleModel.body, []).as("replace_replacement"),
                        SQL.regexSplit(TextSampleModel.body, ",", []).as("split_source"),
                        SQL.regexSplit(TextSampleModel.label, TextSampleModel.body, []).as("split_pattern")
                    )
                    .filter(TextSampleModel.id == row.id)
                    .first(as: NullableRegexTransformResult.self, on: tx))
            #expect(
                result
                    == NullableRegexTransformResult(
                        replaceSource: nil, replacePattern: nil, replaceReplacement: nil, splitSource: nil, splitPattern: nil))
        }
    }

    @Test func regexTransformArgumentsRemainBoundAndComposeWithExistingStringFunctions() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let source = "a'%_\\b"
            let pattern = #"(['%_\\])"#
            let replacement = #"<\1>$1'\\"#
            let row = try await seedTextSample(on: tx, label: source, body: "  AA  BB  ")
            let normalized: Expr<String?> = SQL.regexReplace(
                SQL.lower(SQL.trim(SQL.substring(TextSampleModel.body, 1, 99))), #"\s+"#, "-", .global)

            let result = try #require(
                try await TextSampleModel.query()
                    .select(
                        SQL.regexReplace(TextSampleModel.label, pattern, replacement, .global).as("replaced"),
                        normalized.as("normalized"),
                        SQL.regexSplit(normalized, "-", []).as("parts")
                    )
                    .filter(TextSampleModel.id == row.id)
                    .filter(normalized == "aa-bb")
                    .orderBy(SQL.regexSplit(TextSampleModel.label, "[%_]+", []).asc)
                    .first(on: tx))
            #expect(result.0 == "a<'>$1'\\<%>$1'\\<_>$1'\\<\\>$1'\\b")
            #expect(result.1 == "aa-bb")
            #expect(result.2 == ["aa", "bb"])
        }
    }

    @Test func regexReplaceReportsInvalidPatterns() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "invalid-replace", body: nil)

            let error = try await #require(throws: PSQLError.self) {
                try await TextSampleModel.query().select(SQL.regexReplace(TextSampleModel.label, "[", "x", []).as("value")).all(on: tx)
            }
            #expect(error.serverInfo?[.message]?.contains("invalid regular expression") == true)
        }
    }

    @Test func regexSplitReportsInvalidPatterns() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedTextSample(on: tx, label: "invalid-split", body: nil)

            let error = try await #require(throws: PSQLError.self) {
                try await TextSampleModel.query().select(SQL.regexSplit(TextSampleModel.label, "(", []).as("value")).all(on: tx)
            }
            #expect(error.serverInfo?[.message]?.contains("invalid regular expression") == true)
        }
    }

    // The locking tests hold a lock in one transaction and query from another, on a real table of their own, since a
    // `TEMP` table is visible to one session only. rust-dbkit's tests share one table and tell their rows apart by a token.

    @Test(.timeLimit(.minutes(1))) func lockingForUpdateBlocksUntilFirstTransactionReleasesLock() async throws {
        try await withRealTable("blocking_lock_rows", columns: lockRowColumns) { db in
            let rowID = try #require(
                try await BlockingLockRowModel.insert(BlockingLockRowModel.Insert(note: "row-1")).returningAll().first(on: db)?.id)

            let waiter = try await db.transaction { tx1 in
                let locked = try await BlockingLockRowModel.query().filter(BlockingLockRowModel.id == rowID).forUpdate().first(on: tx1)
                #expect(locked != nil)
                let holder = try #require(try await tx1.query("SELECT pg_backend_pid()").collect().first?.decode(Int32.self))

                let waiter = Task {
                    try await db.transaction { tx2 in
                        try await BlockingLockRowModel.query().filter(BlockingLockRowModel.id == rowID).forUpdate().first(on: tx2)?.id
                    }
                }
                try await waitUntilBlocked(by: holder, on: db)
                return waiter
            }

            // The first transaction committed when its body returned, which released the lock.
            #expect(try await waiter.value == rowID)
        }
    }

    @Test func lockingSkipLockedSkipsRowsLockedByAnotherTransaction() async throws {
        try await withRealTable("skip_locked_rows", columns: lockRowColumns) { db in
            let first = try #require(
                try await SkipLockedRowModel.insert(SkipLockedRowModel.Insert(note: "first")).returningAll().first(on: db))
            let second = try #require(
                try await SkipLockedRowModel.insert(SkipLockedRowModel.Insert(note: "second")).returningAll().first(on: db))

            try await db.transaction { tx1 in
                let lockedFirst = try await SkipLockedRowModel.query().filter(SkipLockedRowModel.id == first.id).forUpdate().first(on: tx1)
                #expect(lockedFirst != nil)

                let ids = try await db.transaction { tx2 in
                    try await SkipLockedRowModel.query().orderBy(SkipLockedRowModel.id.asc).forUpdate(.skipLocked).all(on: tx2).map(\.id)
                }
                #expect(ids == [second.id])
            }
        }
    }

    @Test func lockingNowaitErrorsImmediatelyWhenRowIsLocked() async throws {
        try await withRealTable("nowait_lock_rows", columns: lockRowColumns) { db in
            let row = try #require(
                try await NoWaitLockRowModel.insert(NoWaitLockRowModel.Insert(note: "locked")).returningAll().first(on: db))

            try await db.transaction { tx1 in
                _ = try await NoWaitLockRowModel.query().filter(NoWaitLockRowModel.id == row.id).forUpdate().first(on: tx1)

                let error = try await #require(throws: PSQLError.self, "NOWAIT should fail when the row is already locked") {
                    try await db.transaction { tx2 in
                        _ = try await NoWaitLockRowModel.query().filter(NoWaitLockRowModel.id == row.id).forUpdate(.noWait).first(on: tx2)
                    }
                }
                #expect(error.serverInfo?[.sqlState] == "55P03")
            }
        }
    }

    /// Without contention, one transaction suffices, so this one locks a row of a `TEMP` table.
    @Test func lockingNowaitSucceedsWithoutLockContention() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Free", email: "free@db.com")

            let selected = try await UserModel.query().filter(UserModel.id == user.id).forUpdate(.noWait).first(on: tx)
            #expect(selected?.id == user.id)
        }
    }

    @Test func lockingForUpdateWithLimitLocksOnlySelectedRows() async throws {
        try await withRealTable("limit_lock_rows", columns: lockRowColumns) { db in
            let first = try #require(
                try await LimitLockRowModel.insert(LimitLockRowModel.Insert(note: "first")).returningAll().first(on: db))
            let second = try #require(
                try await LimitLockRowModel.insert(LimitLockRowModel.Insert(note: "second")).returningAll().first(on: db))

            try await db.transaction { tx1 in
                let selected = try await LimitLockRowModel.query().orderBy(LimitLockRowModel.id.asc).limit(1).forUpdate().all(on: tx1)
                #expect(selected.map(\.id) == [first.id])

                // The failed query aborts the second transaction, so the query that succeeds runs first.
                let error = try await #require(throws: PSQLError.self, "first row should be locked by tx1") {
                    try await db.transaction { tx2 in
                        let secondRow = try await LimitLockRowModel.query()
                            .filter(LimitLockRowModel.id == second.id)
                            .forUpdate(.noWait)
                            .first(on: tx2)
                        #expect(secondRow?.id == second.id, "second row should not be locked by tx1")
                        _ = try await LimitLockRowModel.query().filter(LimitLockRowModel.id == first.id).forUpdate(.noWait).first(on: tx2)
                    }
                }
                #expect(error.serverInfo?[.sqlState] == "55P03")
            }
        }
    }
}

private let lockRowColumns = "id BIGSERIAL PRIMARY KEY, note TEXT NOT NULL"

/// Returns once another connection waits for a lock held by the backend with process ID `holder`.
private func waitUntilBlocked(by holder: Int32, on db: Database) async throws {
    let blocked: PostgresQuery = "SELECT count(*) FROM pg_stat_activity WHERE \(holder) = ANY(pg_blocking_pids(pid))"
    while try await db.query(blocked).collect().first?.decode(Int64.self) == 0 {
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// rust-dbkit's `setup_schema`, with the temp tables of the tests ported so far.
private func setupSchema(on tx: Transaction) async throws {
    try await tx.query("CREATE TEMP TABLE users (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL, region TEXT)")
    try await tx.query(
        """
        CREATE TEMP TABLE todos (
            id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL, title TEXT NOT NULL, note TEXT, is_complete BOOLEAN NOT NULL DEFAULT false
        )
        """)
    try await tx.query("CREATE TEMP TABLE tags (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL)")
    try await tx.query("CREATE TEMP TABLE todo_tags (todo_id BIGINT NOT NULL, tag_id BIGINT NOT NULL, PRIMARY KEY (todo_id, tag_id))")
    try await tx.query("CREATE TEMP TABLE nullable_rows (id BIGSERIAL PRIMARY KEY, note TEXT NULL)")
    try await tx.query(
        "CREATE TEMP TABLE order_lines (order_id BIGINT NOT NULL, line_id BIGINT NOT NULL, note TEXT NOT NULL, PRIMARY KEY (order_id, line_id))"
    )
    try await tx.query(
        """
        CREATE TEMP TABLE run_payloads (
            target_id BIGINT NOT NULL, run_id BIGINT NOT NULL, payload TEXT NOT NULL, source TEXT NOT NULL, version BIGINT NOT NULL,
            PRIMARY KEY (target_id, run_id)
        )
        """)
    try await tx.query("CREATE TEMP TABLE profiles (id BIGSERIAL PRIMARY KEY, tags TEXT[] NOT NULL)")
    try await tx.query("CREATE TEMP TABLE json_rows (id BIGSERIAL PRIMARY KEY, data JSONB NOT NULL)")
    try await tx.query(
        "CREATE TEMP TABLE sales (id BIGSERIAL PRIMARY KEY, region TEXT NOT NULL, amount BIGINT NOT NULL, created_at TIMESTAMP NOT NULL)")
    try await tx.query(
        "CREATE TEMP TABLE events (id UUID PRIMARY KEY, name TEXT NOT NULL, starts_at TIMESTAMP NOT NULL, day DATE NOT NULL)")
    try await tx.query(
        "CREATE TEMP TABLE func_rows (id BIGSERIAL PRIMARY KEY, email TEXT, backup_email TEXT, region TEXT, starts_at TIMESTAMP NOT NULL)")
    try await tx.query("CREATE TEMP TABLE text_samples (id BIGSERIAL PRIMARY KEY, label TEXT NOT NULL, body TEXT)")
    try await tx.query(
        "CREATE TEMP TABLE renamed_parents (id BIGSERIAL PRIMARY KEY, type TEXT NOT NULL, external_ref TEXT NOT NULL, label TEXT NOT NULL, UNIQUE (type))"
    )
    try await tx.query(
        "CREATE TEMP TABLE renamed_children (id BIGSERIAL PRIMARY KEY, parent_id BIGINT NOT NULL, type TEXT NOT NULL, sort_key BIGINT NOT NULL)"
    )
}

private func seedFuncRow(on tx: Transaction, email: String?, backupEmail: String?, region: String?, startsAt: Date) async throws
    -> FuncRowModel
{
    try #require(
        try await FuncRowModel.insert(FuncRowModel.Insert(email: email, backupEmail: backupEmail, region: region, startsAt: startsAt))
            .returningAll().first(on: tx))
}

private func seedTextSample(on tx: Transaction, label: String, body: String?) async throws -> TextSampleModel {
    try #require(try await TextSampleModel.insert(TextSampleModel.Insert(label: label, body: body)).returningAll().first(on: tx))
}

private func seedUser(on tx: Transaction, name: String, email: String) async throws -> UserModel {
    try #require(try await UserModel.insert(UserModel.Insert(name: name, email: email)).returningAll().first(on: tx))
}

private func seedTodo(on tx: Transaction, userID: Int64, title: String) async throws -> TodoModel {
    try #require(try await TodoModel.insert(TodoModel.Insert(userID: userID, title: title)).returningAll().first(on: tx))
}

private func seedTag(on tx: Transaction, name: String) async throws -> TagModel {
    try #require(try await TagModel.insert(TagModel.Insert(name: name)).returningAll().first(on: tx))
}

private func seedTodoTag(on tx: Transaction, todoID: Int64, tagID: Int64) async throws {
    try await TodoTagModel.insert(TodoTagModel.Insert(todoID: todoID, tagID: tagID)).execute(on: tx)
}

private func seedNullableRow(on tx: Transaction, note: String?) async throws -> NullableRowModel {
    try #require(try await NullableRowModel.insert(NullableRowModel.Insert(note: note)).returningAll().first(on: tx))
}

private func seedOrderLine(on tx: Transaction, _ orderID: Int64, _ lineID: Int64, note: String) async throws -> OrderLineModel {
    try #require(
        try await OrderLineModel.insert(OrderLineModel.Insert(orderID: orderID, lineID: lineID, note: note)).returningAll().first(on: tx))
}

private func seedRunPayload(
    on tx: Transaction, _ targetID: Int64, _ runID: Int64, payload: String, source: String, version: Int64
) async throws -> RunPayloadModel {
    try #require(
        try await RunPayloadModel.insert(
            RunPayloadModel.Insert(targetID: targetID, runID: runID, payload: payload, source: source, version: version)
        )
        .returningAll().first(on: tx))
}

private func runPayloads(_ targetID: Int64, _ runID: Int64, on tx: Transaction) async throws -> [RunPayloadModel] {
    try await RunPayloadModel.query().filter(RunPayloadModel.targetID == targetID).filter(RunPayloadModel.runID == runID).all(on: tx)
}

private func orderLine(_ orderID: Int64, _ lineID: Int64, on tx: Transaction) async throws -> OrderLineModel? {
    try await OrderLineModel.query().filter(OrderLineModel.orderID == orderID).filter(OrderLineModel.lineID == lineID).first(on: tx)
}

private func seedRenamedParent(on tx: Transaction, kind: String, externalReference: String, label: String) async throws
    -> RenamedParentModel
{
    try #require(
        try await RenamedParentModel.insert(RenamedParentModel.Insert(kind: kind, externalReference: externalReference, label: label))
            .returningAll().first(on: tx))
}

private func seedRenamedChild(on tx: Transaction, parentID: Int64, kind: String, rankKey: Int64) async throws -> RenamedChildModel {
    try #require(
        try await RenamedChildModel.insert(RenamedChildModel.Insert(parentID: parentID, kind: kind, rankKey: rankKey)).returningAll()
            .first(on: tx))
}
