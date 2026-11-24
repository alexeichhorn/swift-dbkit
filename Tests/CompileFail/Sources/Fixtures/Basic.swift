import DBKit

private func useModelAPI() {
    _ = UserModel.schema.table
    _ = UserModel.email
    let query = UserModel.query().filter(UserModel.email == "a@b.com").limit(1)
    _ = query.render()
    // Waits for slice 4: `UserModel.insert(UserModel.Insert(…))`, `update()` and `delete()`.
    // Waits for slice 17: a `TodoModel` with `@HasMany`/`@BelongsTo`, `.with(\.todos)`, nested loads, a loaded row's `todos`.
    // Waits for slice 19: `load(_:on:)` on an unloaded row.
}
