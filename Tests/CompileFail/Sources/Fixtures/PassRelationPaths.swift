import DBKit

// A path filters, orders and projects without loading its relation; `with(_:)` still decides what's loaded. Its
// columns are nullable because the outer join can find no row, and an already nullable column stays singly optional.

private func pathsLeaveLoadingToWith(on executor: some DatabaseExecutor) async throws {
    let enabled = PathRecordModel.Relations.owner.enabled == true
    let _: [PathRecordModel] = try await PathRecordModel.query().filter(enabled).all(on: executor)
    let _: [PathRecordModel.Loaded<PathMemberModel?>] = try await PathRecordModel.query()
        .with(\.owner, .joined)
        .filter(enabled)
        .all(on: executor)
    let _: [PathRecordModel.Loaded<PathMemberModel?>] = try await PathRecordModel.query()
        .filter(enabled)
        .with(\.owner, .selectIn)
        .all(on: executor)
    let _: [PathRecordModel.Loaded<PathMemberModel.Loaded<PathOrganizationModel?>?>] = try await PathRecordModel.query()
        .filter(PathRecordModel.Relations.owner.organization.label == "north")
        .with(\.owner, .joined) { $0.with(\.organization, .joined) }
        .all(on: executor)
}

private func pathColumnsAreNullable() {
    let owner = PathRecordModel.Relations.owner
    let _: Column<PathMemberModel, Bool> = PathMemberModel.enabled
    let _: Expr<Bool?> = owner.enabled
    let _: Expr<Int64?> = owner.id
    let _: Expr<String?> = owner.label
    let _: Expr<String?> = owner.note
    let _: Expr<String?> = owner.organization.label
    let _: Expr<Bool?> = owner.enabled == true
    let _: Expr<Bool?> = owner.score > 10
    let _: Expr<Bool?> = owner.score > PathMemberModel.score
    let _: Expr<Bool?> = owner.note == nil
    let _: Expr<Bool?> = owner.label.in(["atlas", "birch"])
    let _: Expr<Bool?> = owner.label.ilike("a%")
    let _: Expr<Bool?> = owner.enabled == true && PathRecordModel.enabled == true
    let _: Expr<Bool?> = !(owner.enabled == true)
    let _: Expr<Bool> = owner.id.isNull
    let _: Expr<Bool> = owner.note.isNotNull
    let _: Expr<Int32?> = owner.score + 1
    let _: Expr<String?> = SQL.lower(owner.label)
    let _: Expr<String> = SQL.coalesce(owner.note, "missing")
}

private func pathsAreReusableValues() {
    let path = PathRecordModel.Relations.owner
    let column = path.code
    let predicate = column == "a"
    let _: Query<PathRecordModel> = PathRecordModel.query().filter(predicate)
    _ = PathRecordModel.query().filter(predicate).orderBy(path.label.asc)
    _ = PathRecordModel.query().select(path.label.as("owner_label"), path.organization.label.as("organization_label"))
    _ = PathRecordModel.query().join(\.owner).filter(column == "a")
    _ = PathRecordModel.query().leftJoin(\.owner).filter(path.id.isNull)
}
