import DBKit

// A path reaches only the target's columns and belongs-to relations.

private func pathsNameExistingMembers() {
    _ = PathRecordModel.Relations.owner.enabled == true
    _ = PathRecordModel.Relations.owner.unknown == true  // error: 'unknown'
    _ = PathRecordModel.Relations.owner.organization.unknown == true  // error: 'unknown'
    // A to-many relation is no path; join it or use `whereExists`.
    _ = UserModel.Relations.todos.title == "x"  // error: 'title'
}
