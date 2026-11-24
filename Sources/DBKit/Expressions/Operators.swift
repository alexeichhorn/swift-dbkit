// Operators are declared only for `SQLExpression` operands (with a plain value on at most one side),
// so they never take part in type-checking ordinary Swift code.

// MARK: - Comparison

public func == <L: SQLExpression>(lhs: L, rhs: L.Value.NonNull) -> Expr<Bool> { compare(lhs.sqlNode, "=", rhs.sqlNode) }
public func != <L: SQLExpression>(lhs: L, rhs: L.Value.NonNull) -> Expr<Bool> { compare(lhs.sqlNode, "<>", rhs.sqlNode) }
public func < <L: SQLExpression>(lhs: L, rhs: L.Value.NonNull) -> Expr<Bool> { compare(lhs.sqlNode, "<", rhs.sqlNode) }
public func <= <L: SQLExpression>(lhs: L, rhs: L.Value.NonNull) -> Expr<Bool> { compare(lhs.sqlNode, "<=", rhs.sqlNode) }
public func > <L: SQLExpression>(lhs: L, rhs: L.Value.NonNull) -> Expr<Bool> { compare(lhs.sqlNode, ">", rhs.sqlNode) }
public func >= <L: SQLExpression>(lhs: L, rhs: L.Value.NonNull) -> Expr<Bool> { compare(lhs.sqlNode, ">=", rhs.sqlNode) }

private func compare(_ lhs: SQLNode, _ op: String, _ rhs: SQLNode) -> Expr<Bool> {
    Expr(.infix(lhs, op, rhs, parenthesized: false))
}

// MARK: - Logic

public func && <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<Bool> where L.Value.NonNull == Bool, R.Value.NonNull == Bool {
    Expr(.infix(lhs.sqlNode, "AND", rhs.sqlNode))
}
public func || <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<Bool> where L.Value.NonNull == Bool, R.Value.NonNull == Bool {
    Expr(.infix(lhs.sqlNode, "OR", rhs.sqlNode))
}
public prefix func ! <E: SQLExpression>(expression: E) -> Expr<Bool> where E.Value.NonNull == Bool {
    Expr(.sequence([.raw("NOT ("), expression.sqlNode, .raw(")")]))
}
