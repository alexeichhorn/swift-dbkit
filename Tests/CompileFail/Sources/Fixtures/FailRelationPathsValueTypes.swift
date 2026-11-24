import DBKit

// A path column takes values and functions of its own type.

private func pathColumnsKeepTheirValueTypes() {
    let owner = PathRecordModel.Relations.owner
    _ = owner.enabled == true
    _ = owner.enabled == "enabled"  // error: '=='
    _ = owner.score > "high"  // error: '>'
    _ = SQL.lower(owner.score)  // error: lower
}
