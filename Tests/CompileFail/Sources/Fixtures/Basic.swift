import DBKit

private func useModelAPI() {
    _ = UserModel.schema.table
    _ = UserModel.email
    let query = UserModel.query().filter(UserModel.email == "a@b.com").limit(1)
    _ = query.render()
    _ = UserModel.insert(UserModel.Insert(name: "Alex", email: "a@b.com"))
    _ = UserModel.update()
    _ = UserModel.delete()
    // Waits for slice 17: a `TodoModel` with `@HasMany`/`@BelongsTo`, `.with(\.todos)`, nested loads, a loaded row's `todos`.
    // Waits for slice 19: `load(_:on:)` on an unloaded row.
    _ = UserModel.Insert(name: "Alex", email: "a@b.com")
}
