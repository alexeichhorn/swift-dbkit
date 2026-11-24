// Operators are declared only for `SQLExpression` operands (with a plain value on at most one side),
// so they never take part in type-checking ordinary Swift code.

// MARK: - Comparison
//
// A comparison is `Expr<Bool?>` when its operand is nullable, since a comparison with NULL is NULL. A nullable
// operand takes its optional type, so `nil` and optional values compile only against nullable expressions.

/// `nil` compiles to `IS NULL`.
public func == <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compareOrNullCheck(lhs, "=", rhs, "IS NULL") }
/// `nil` compiles to `IS NOT NULL`.
public func != <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compareOrNullCheck(lhs, "<>", rhs, "IS NOT NULL") }
public func < <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compare(lhs.sqlNode, "<", rhs.sqlNode) }
public func <= <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compare(lhs.sqlNode, "<=", rhs.sqlNode) }
public func > <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compare(lhs.sqlNode, ">", rhs.sqlNode) }
public func >= <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compare(lhs.sqlNode, ">=", rhs.sqlNode) }

private func compare<Result>(_ lhs: SQLNode, _ op: String, _ rhs: SQLNode) -> Expr<Result> {
    Expr(.infix(lhs, op, rhs, parenthesized: false))
}

private func compareOrNullCheck<L: SQLExpression, Result>(_ lhs: L, _ op: String, _ rhs: L.Value, _ nullCheck: String) -> Expr<Result> {
    if case .null = rhs.sqlNode { return Expr(.sequence([lhs.sqlNode, .raw(" \(nullCheck)")])) }
    return compare(lhs.sqlNode, op, rhs.sqlNode)
}

// MARK: - Logic

// Three-valued: the result is `Expr<Bool?>` when either operand is nullable. The two overloads of each operator split
// on the right operand's nullability, so exactly one applies; `ExpressibleByNilLiteral` marks a nullable value.

public func && <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value.AsBool> where L.Value.NonNull == Bool, R.Value == Bool {
    Expr(.infix(lhs.sqlNode, "AND", rhs.sqlNode))
}
public func && <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<Bool?>
where L.Value.NonNull == Bool, R.Value: ExpressibleByNilLiteral, R.Value.NonNull == Bool {
    Expr(.infix(lhs.sqlNode, "AND", rhs.sqlNode))
}
public func || <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value.AsBool> where L.Value.NonNull == Bool, R.Value == Bool {
    Expr(.infix(lhs.sqlNode, "OR", rhs.sqlNode))
}
public func || <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<Bool?>
where L.Value.NonNull == Bool, R.Value: ExpressibleByNilLiteral, R.Value.NonNull == Bool {
    Expr(.infix(lhs.sqlNode, "OR", rhs.sqlNode))
}
public prefix func ! <E: SQLExpression>(expression: E) -> Expr<E.Value.AsBool> where E.Value.NonNull == Bool {
    Expr(.sequence([.raw("NOT ("), expression.sqlNode, .raw(")")]))
}

// MARK: - NULL fallback

/// `COALESCE(lhs, rhs)`: replaces NULL with a non-null value, producing a non-null expression.
public func ?? <L: SQLExpression, W: SQLValue>(lhs: L, rhs: W) -> Expr<W> where L.Value == W? {
    Expr(.function("COALESCE", [lhs.sqlNode, rhs.sqlNode]))
}
public func ?? <L: SQLExpression, R: SQLExpression, W: SQLValue>(lhs: L, rhs: R) -> Expr<W> where L.Value == W?, R.Value == W {
    Expr(.function("COALESCE", [lhs.sqlNode, rhs.sqlNode]))
}
public func ?? <L: SQLExpression, R: SQLExpression, W: SQLValue>(lhs: L, rhs: R) -> Expr<W?> where L.Value == W?, R.Value == W? {
    Expr(.function("COALESCE", [lhs.sqlNode, rhs.sqlNode]))
}
/// Operands of the same type also match the standard library's `??`, which drops the fallback. Requirements on `E`
/// alone make the type checker try this overload first.
public func ?? <E: SQLExpression>(lhs: E, rhs: E) -> Expr<E.Value> where E.Value: ExpressibleByNilLiteral {
    Expr(.function("COALESCE", [lhs.sqlNode, rhs.sqlNode]))
}
