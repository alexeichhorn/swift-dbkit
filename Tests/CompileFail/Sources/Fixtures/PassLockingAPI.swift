import DBKit

// `forUpdate` takes the waiting behaviour as its argument and combines with filtering, ordering and pagination.

private func lockingQueries() {
    _ = UserModel.query().forUpdate().render()

    _ = UserModel.query()
        .filter(UserModel.email.ilike("%@example.com"))
        .orderBy(UserModel.id.asc)
        .limit(50)
        .forUpdate(.skipLocked)
        .render()

    _ = UserModel.query()
        .orderBy(UserModel.id.desc)
        .offset(10)
        .forUpdate(.noWait)
        .render()
}
