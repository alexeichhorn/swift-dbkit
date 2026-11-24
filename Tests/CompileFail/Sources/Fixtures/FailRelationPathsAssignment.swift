import DBKit

// A path filters through the joined row; it never becomes an assignment to a column of the query's own table.

private func pathsAreReadOnly() {
    _ = PathRecordModel.query().filter(PathRecordModel.Relations.owner.enabled == true)
    _ = PathRecordModel.update().set(PathRecordModel.Relations.owner.enabled, to: true)  // error: 'Expr<Bool?>'
}
