import DBKit

// Two relations to one model load and filter independently, and a self-reference loads and filters several levels deep.

private func siblingAndSelfRelationsLoad(on executor: some DatabaseExecutor) async throws {
    let _: [PathAssignmentModel.Loaded<PathMemberModel?, NotLoaded>] = try await PathAssignmentModel.query()
        .with(\.first, .joined)
        .all(on: executor)
    let _: [PathAssignmentModel.Loaded<NotLoaded, PathMemberModel?>] = try await PathAssignmentModel.query()
        .with(\.second, .joined)
        .all(on: executor)
    let _: [PathAssignmentModel.Loaded<PathMemberModel?, PathMemberModel?>] = try await PathAssignmentModel.query()
        .with(\.second, .joined)
        .with(\.first, .joined)
        .all(on: executor)
    let _: [PathAssignmentModel.Loaded<PathMemberModel.Loaded<PathOrganizationModel?>?, PathMemberModel?>] =
        try await PathAssignmentModel.query()
        .with(\.first, .joined) { $0.with(\.organization, .joined) }
        .with(\.second, .selectIn)
        .all(on: executor)

    let _: [PathNodeModel.Loaded<PathNodeModel.Loaded<PathNodeModel?>?>] = try await PathNodeModel.query()
        .filter(PathNodeModel.Relations.parent.parent.label == "root")
        .with(\.parent, .joined) { $0.with(\.parent, .joined) }
        .all(on: executor)
}

private func siblingAndSelfPathsFilter() {
    let first = PathAssignmentModel.Relations.first
    let second = PathAssignmentModel.Relations.second
    _ = PathAssignmentModel.query()
        .filter(first.enabled == true)
        .filter(second.enabled == false)
        .filter(first.score > second.score)
    _ = PathAssignmentModel.query()
        .filter(first.organization.label == "north")
        .filter(second.organization.label == "south")
    _ = PathNodeModel.query().filter(PathNodeModel.Relations.parent.parent.parent.id == 1)
}
