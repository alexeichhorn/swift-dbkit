import DBKit

// A path column is nullable, and an already nullable column doesn't become doubly optional.

private func pathColumnsStayNullable() {
    let owner = PathRecordModel.Relations.owner
    let _: Expr<Bool?> = owner.enabled == true
    let _: Expr<Bool> = owner.enabled == true  // error: 'Expr<Bool>'
    let _: Expr<String> = owner.label  // error: 'Expr<String>'
    let _: Expr<String??> = owner.note  // error: 'Expr<String??>'
}
