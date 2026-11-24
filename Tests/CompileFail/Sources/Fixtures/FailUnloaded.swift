import DBKit

private func readUnloadedRelations(user: UserModel, unloaded: UserModel.Loaded<NotLoaded>) {
    _ = user.todos  // error: relation 'todos' is not loaded; add .with(\.todos) to the query
    _ = unloaded.todos  // error: relation 'todos' is not loaded; add .with(\.todos) to the query
}
