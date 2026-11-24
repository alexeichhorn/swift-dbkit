import DBKit

// A value on the left of a path column keeps the operand rules of a plain column. rust-dbkit also rejects `Int16` and
// `Double` values with an `Int32` column in `+` and `*`; this port promotes mixed numeric types as PostgreSQL does (see
// "Ported Beyond The Kit" in docs/rust-parity.md).

private func operatorsKeepTheirOperandRules() {
    let owner = PathRecordModel.Relations.owner
    _ = Int32(1) + owner.label  // error: 'Expr<String?>'
    _ = Int32(1) - owner.enabled  // error: 'Expr<Bool?>'
    _ = UInt32(1) + owner.score  // error: '+'
    _ = Double(1) & owner.score  // error: 'Double'
    _ = true | owner.enabled  // error: '|'
    _ = Int32(1) ^ owner.note  // error: '^'

    // PostgreSQL's shift counts are `smallint` or `integer`, not `bigint` or text.
    _ = Int32(1) << owner.id  // error: '<<'
    _ = Int64(1) >> owner.organization.id  // error: '>>'
    _ = Int32(1) << owner.label  // error: '<<'

    // A value on the left doesn't remove the outer join's NULL.
    let _: Expr<Int32> = Int32(1) + owner.score  // error: 'Expr<Int32>'
}
