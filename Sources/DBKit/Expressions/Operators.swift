// Operators are declared only for `SQLExpression` operands (with a plain value on at most one side),
// so they never take part in type-checking ordinary Swift code.

// MARK: - Comparison
//
// A comparison is `Expr<Bool?>` when an operand is nullable, since a comparison with NULL is NULL. A nullable
// operand takes its optional type, so `nil` and optional values compile only against nullable expressions.
//
// Between two expressions, the two overloads of each operator split on the right operand's nullability, as `&&` does.
// `R.Value.AsBool: SQLValue` holds only for a required `R`, whose `AsBool` is `Bool`. It is a conformance rather than
// `== Bool` so that a nullable comparison declared `Expr<Bool>` is reported as a result type mismatch.

/// `nil` compiles to `IS NULL`.
public func == <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compareOrNullCheck(lhs, "=", rhs, "IS NULL") }
public func == <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value.AsBool>
where R.Value.NonNull == L.Value.NonNull, R.Value.AsBool: SQLValue {
    compare(lhs.sqlNode, "=", rhs.sqlNode)
}
public func == <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<Bool?>
where R.Value: ExpressibleByNilLiteral, R.Value.NonNull == L.Value.NonNull {
    compare(lhs.sqlNode, "=", rhs.sqlNode)
}
/// `nil` compiles to `IS NOT NULL`.
public func != <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compareOrNullCheck(lhs, "<>", rhs, "IS NOT NULL") }
public func != <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value.AsBool>
where R.Value.NonNull == L.Value.NonNull, R.Value.AsBool: SQLValue {
    compare(lhs.sqlNode, "<>", rhs.sqlNode)
}
public func != <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<Bool?>
where R.Value: ExpressibleByNilLiteral, R.Value.NonNull == L.Value.NonNull {
    compare(lhs.sqlNode, "<>", rhs.sqlNode)
}
public func < <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compare(lhs.sqlNode, "<", rhs.sqlNode) }
public func < <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value.AsBool>
where R.Value.NonNull == L.Value.NonNull, R.Value.AsBool: SQLValue {
    compare(lhs.sqlNode, "<", rhs.sqlNode)
}
public func < <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<Bool?>
where R.Value: ExpressibleByNilLiteral, R.Value.NonNull == L.Value.NonNull {
    compare(lhs.sqlNode, "<", rhs.sqlNode)
}
public func <= <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compare(lhs.sqlNode, "<=", rhs.sqlNode) }
public func <= <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value.AsBool>
where R.Value.NonNull == L.Value.NonNull, R.Value.AsBool: SQLValue {
    compare(lhs.sqlNode, "<=", rhs.sqlNode)
}
public func <= <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<Bool?>
where R.Value: ExpressibleByNilLiteral, R.Value.NonNull == L.Value.NonNull {
    compare(lhs.sqlNode, "<=", rhs.sqlNode)
}
public func > <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compare(lhs.sqlNode, ">", rhs.sqlNode) }
public func > <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value.AsBool>
where R.Value.NonNull == L.Value.NonNull, R.Value.AsBool: SQLValue {
    compare(lhs.sqlNode, ">", rhs.sqlNode)
}
public func > <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<Bool?>
where R.Value: ExpressibleByNilLiteral, R.Value.NonNull == L.Value.NonNull {
    compare(lhs.sqlNode, ">", rhs.sqlNode)
}
public func >= <L: SQLExpression>(lhs: L, rhs: L.Value) -> Expr<L.Value.AsBool> { compare(lhs.sqlNode, ">=", rhs.sqlNode) }
public func >= <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value.AsBool>
where R.Value.NonNull == L.Value.NonNull, R.Value.AsBool: SQLValue {
    compare(lhs.sqlNode, ">=", rhs.sqlNode)
}
public func >= <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<Bool?>
where R.Value: ExpressibleByNilLiteral, R.Value.NonNull == L.Value.NonNull {
    compare(lhs.sqlNode, ">=", rhs.sqlNode)
}

private func compare<Result>(_ lhs: SQLNode, _ op: String, _ rhs: SQLNode) -> Expr<Result> {
    Expr(.comparison(lhs, op, rhs))
}

private func compareOrNullCheck<L: SQLExpression, Result>(_ lhs: L, _ op: String, _ rhs: L.Value, _ nullCheck: String) -> Expr<Result> {
    if case .null = rhs.sqlNode { return Expr(.nullCheck(lhs.sqlNode, nullCheck)) }
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

// MARK: - Arithmetic
//
// Operands of one type give that type, nullable when either operand is. A literal takes the other operand's type.

public func + <L: SQLExpression>(lhs: L, rhs: L.Value.NonNull) -> Expr<L.Value> where L.Value.NonNull: SQLAdditive {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
public func + <R: SQLExpression>(lhs: R.Value.NonNull, rhs: R) -> Expr<R.Value> where R.Value.NonNull: SQLAdditive {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
public func + <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value> where L.Value == R.Value, L.Value.NonNull: SQLAdditive {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
public func + <L: SQLExpression, R: SQLExpression, V: SQLAdditive>(lhs: L, rhs: R) -> Expr<V?> where L.Value == V, R.Value == V? {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
public func + <L: SQLExpression, R: SQLExpression, V: SQLAdditive>(lhs: L, rhs: R) -> Expr<V?> where L.Value == V?, R.Value == V {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}

public func - <L: SQLExpression>(lhs: L, rhs: L.Value.NonNull) -> Expr<L.Value> where L.Value.NonNull: SQLAdditive {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
public func - <R: SQLExpression>(lhs: R.Value.NonNull, rhs: R) -> Expr<R.Value> where R.Value.NonNull: SQLAdditive {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
public func - <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value> where L.Value == R.Value, L.Value.NonNull: SQLAdditive {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
public func - <L: SQLExpression, R: SQLExpression, V: SQLAdditive>(lhs: L, rhs: R) -> Expr<V?> where L.Value == V, R.Value == V? {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
public func - <L: SQLExpression, R: SQLExpression, V: SQLAdditive>(lhs: L, rhs: R) -> Expr<V?> where L.Value == V?, R.Value == V {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}

public func * <L: SQLExpression>(lhs: L, rhs: L.Value.NonNull) -> Expr<L.Value> where L.Value.NonNull: SQLNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
public func * <R: SQLExpression>(lhs: R.Value.NonNull, rhs: R) -> Expr<R.Value> where R.Value.NonNull: SQLNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
public func * <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value> where L.Value == R.Value, L.Value.NonNull: SQLNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
public func * <L: SQLExpression, R: SQLExpression, V: SQLNumeric>(lhs: L, rhs: R) -> Expr<V?> where L.Value == V, R.Value == V? {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
public func * <L: SQLExpression, R: SQLExpression, V: SQLNumeric>(lhs: L, rhs: R) -> Expr<V?> where L.Value == V?, R.Value == V {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}

/// Integer division keeps PostgreSQL's integer semantics; `cast(to: Double.self)` an operand for fractions.
public func / <L: SQLExpression>(lhs: L, rhs: L.Value.NonNull) -> Expr<L.Value> where L.Value.NonNull: SQLNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
public func / <R: SQLExpression>(lhs: R.Value.NonNull, rhs: R) -> Expr<R.Value> where R.Value.NonNull: SQLNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
public func / <L: SQLExpression, R: SQLExpression>(lhs: L, rhs: R) -> Expr<L.Value> where L.Value == R.Value, L.Value.NonNull: SQLNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
public func / <L: SQLExpression, R: SQLExpression, V: SQLNumeric>(lhs: L, rhs: R) -> Expr<V?> where L.Value == V, R.Value == V? {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
public func / <L: SQLExpression, R: SQLExpression, V: SQLNumeric>(lhs: L, rhs: R) -> Expr<V?> where L.Value == V?, R.Value == V {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}

// MARK: - Arithmetic between numeric types
//
// PostgreSQL's promotion: the wider integer, and `Double` for an integer with `Float` or `Double`, or for `Float` with
// `Double`. The result is nullable when either operand is. Three overloads per type of the left operand (a required
// expression, a nullable one, a value) pick the result from the right operand's `SQLMixedNumeric` table. Keyed on the
// left type, they fail alike for a type without promotion such as `Date` or `Decimal`, so the compiler's error names
// both operand types. They are disfavored so that the same-type overloads above win wherever they apply, which gives a
// literal the other operand's type: an `Int16` column `+ 1` is `Expr<Int16>`, not the `Expr<Int64>` of Swift's default
// literal type `Int`.

@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt16>
where L.Value == Int16, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt16?>
where L.Value == Int16?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <R: SQLExpression>(lhs: Int16, rhs: R) -> Expr<R.Value.WithInt16> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt32>
where L.Value == Int32, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt32?>
where L.Value == Int32?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <R: SQLExpression>(lhs: Int32, rhs: R) -> Expr<R.Value.WithInt32> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt64>
where L.Value == Int64, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt64?>
where L.Value == Int64?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <R: SQLExpression>(lhs: Int64, rhs: R) -> Expr<R.Value.WithInt64> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt64> where L.Value == Int, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt64?>
where L.Value == Int?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <R: SQLExpression>(lhs: Int, rhs: R) -> Expr<R.Value.WithInt64> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithFloat>
where L.Value == Float, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithFloat?>
where L.Value == Float?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <R: SQLExpression>(lhs: Float, rhs: R) -> Expr<R.Value.WithFloat> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.AsDouble>
where L.Value == Double, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<Double?> where L.Value == Double?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}
@_disfavoredOverload
public func + <R: SQLExpression>(lhs: Double, rhs: R) -> Expr<R.Value.AsDouble> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "+", rhs.sqlNode))
}

@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt16>
where L.Value == Int16, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt16?>
where L.Value == Int16?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <R: SQLExpression>(lhs: Int16, rhs: R) -> Expr<R.Value.WithInt16> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt32>
where L.Value == Int32, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt32?>
where L.Value == Int32?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <R: SQLExpression>(lhs: Int32, rhs: R) -> Expr<R.Value.WithInt32> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt64>
where L.Value == Int64, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt64?>
where L.Value == Int64?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <R: SQLExpression>(lhs: Int64, rhs: R) -> Expr<R.Value.WithInt64> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt64> where L.Value == Int, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt64?>
where L.Value == Int?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <R: SQLExpression>(lhs: Int, rhs: R) -> Expr<R.Value.WithInt64> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithFloat>
where L.Value == Float, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithFloat?>
where L.Value == Float?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <R: SQLExpression>(lhs: Float, rhs: R) -> Expr<R.Value.WithFloat> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.AsDouble>
where L.Value == Double, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<Double?> where L.Value == Double?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}
@_disfavoredOverload
public func - <R: SQLExpression>(lhs: Double, rhs: R) -> Expr<R.Value.AsDouble> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "-", rhs.sqlNode))
}

@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt16>
where L.Value == Int16, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt16?>
where L.Value == Int16?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <R: SQLExpression>(lhs: Int16, rhs: R) -> Expr<R.Value.WithInt16> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt32>
where L.Value == Int32, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt32?>
where L.Value == Int32?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <R: SQLExpression>(lhs: Int32, rhs: R) -> Expr<R.Value.WithInt32> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt64>
where L.Value == Int64, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt64?>
where L.Value == Int64?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <R: SQLExpression>(lhs: Int64, rhs: R) -> Expr<R.Value.WithInt64> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt64> where L.Value == Int, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt64?>
where L.Value == Int?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <R: SQLExpression>(lhs: Int, rhs: R) -> Expr<R.Value.WithInt64> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithFloat>
where L.Value == Float, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithFloat?>
where L.Value == Float?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <R: SQLExpression>(lhs: Float, rhs: R) -> Expr<R.Value.WithFloat> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.AsDouble>
where L.Value == Double, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<Double?> where L.Value == Double?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}
@_disfavoredOverload
public func * <R: SQLExpression>(lhs: Double, rhs: R) -> Expr<R.Value.AsDouble> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "*", rhs.sqlNode))
}

@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt16>
where L.Value == Int16, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt16?>
where L.Value == Int16?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <R: SQLExpression>(lhs: Int16, rhs: R) -> Expr<R.Value.WithInt16> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt32>
where L.Value == Int32, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt32?>
where L.Value == Int32?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <R: SQLExpression>(lhs: Int32, rhs: R) -> Expr<R.Value.WithInt32> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt64>
where L.Value == Int64, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt64?>
where L.Value == Int64?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <R: SQLExpression>(lhs: Int64, rhs: R) -> Expr<R.Value.WithInt64> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithInt64> where L.Value == Int, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithInt64?>
where L.Value == Int?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <R: SQLExpression>(lhs: Int, rhs: R) -> Expr<R.Value.WithInt64> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.WithFloat>
where L.Value == Float, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.NonNull.WithFloat?>
where L.Value == Float?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <R: SQLExpression>(lhs: Float, rhs: R) -> Expr<R.Value.WithFloat> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<R.Value.AsDouble>
where L.Value == Double, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <L: SQLExpression, R: SQLArgument>(lhs: L, rhs: R) -> Expr<Double?> where L.Value == Double?, R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
@_disfavoredOverload
public func / <R: SQLExpression>(lhs: Double, rhs: R) -> Expr<R.Value.AsDouble> where R.Value: SQLMixedNumeric {
    Expr(.infix(lhs.sqlNode, "/", rhs.sqlNode))
}
