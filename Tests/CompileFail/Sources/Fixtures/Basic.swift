import DBKit

private func useModelAPI(loaded: UserModel.Loaded<[TodoModel]>) {
    _ = UserModel.schema.table
    _ = UserModel.email
    let query = UserModel.query().filter(UserModel.email == "a@b.com").limit(1)
    _ = query.render()
    _ = UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com"))
    _ = UserModel.update()
    _ = UserModel.delete()

    _ = UserModel.Relations.todos
    _ = TodoModel.Relations.user
    let _: Query<UserModel.Loaded<[TodoModel]>> = UserModel.query().with(\.todos)
    let _: Query<UserModel.Loaded<[TodoModel.Loaded<UserModel?>]>> = UserModel.query().with(\.todos) { $0.with(\.user) }
    let _: Query<UserModel.Loaded<[TodoModel.Loaded<UserModel?>]>> = UserModel.query().with(\.todos) { $0.with(\.user, .joined) }
    let _: [TodoModel] = loaded.todos
    let _: (UserModel, Database) async throws -> UserModel.Loaded<[TodoModel]> = { unloaded, db in
        try await unloaded.load(\.todos, on: db)
    }
    _ = UserModel.Insert(name: "Alex", email: "a@b.com")
}
