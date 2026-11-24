import Foundation

/// Typed SQL functions. Results keep the nullability of their inputs where PostgreSQL propagates NULL.
public enum SQL {
    /// `NOW()`: the transaction's start time.
    public static func now() -> Expr<Date> { Expr(.raw("NOW()")) }

    // `COALESCE`, `LEAST` and `GREATEST` take arguments of one type and are nullable only when both arguments are. A
    // plain value takes the other argument's type, so a literal fits the column it is paired with.

    /// `COALESCE(value, fallback)`, same as `value ?? fallback`.
    public static func coalesce<L: SQLExpression, W: SQLValue>(_ value: L, _ fallback: W) -> Expr<W> where L.Value == W? {
        value ?? fallback
    }

    public static func coalesce<L: SQLExpression, R: SQLExpression, W: SQLValue>(_ value: L, _ fallback: R) -> Expr<R.Value>
    where L.Value == W?, R.Value.NonNull == W {
        Expr(.function("COALESCE", [value.sqlNode, fallback.sqlNode]))
    }

    /// A required first argument makes the result required.
    public static func coalesce<L: SQLExpression, R: SQLExpression>(_ value: L, _ fallback: R) -> Expr<L.Value>
    where L.Value == R.Value.NonNull {
        Expr(.function("COALESCE", [value.sqlNode, fallback.sqlNode]))
    }

    /// `DATE_TRUNC('unit', timestamp)`.
    public static func dateTrunc<E: SQLExpression>(_ unit: DateTruncUnit, _ timestamp: E) -> Expr<E.Value> where E.Value.NonNull == Date {
        Expr(.function("DATE_TRUNC", [.raw("'\(unit.rawValue)'"), timestamp.sqlNode]))
    }

    /// `LEAST(…)`. PostgreSQL ignores NULL arguments, so a non-null argument makes the result non-null.
    public static func least<L: SQLExpression>(_ lhs: L, _ rhs: L.Value.NonNull) -> Expr<L.Value.NonNull> {
        Expr(.function("LEAST", [lhs.sqlNode, rhs.sqlNode]))
    }

    public static func least<R: SQLExpression>(_ lhs: R.Value.NonNull, _ rhs: R) -> Expr<R.Value.NonNull> {
        Expr(.function("LEAST", [lhs.sqlNode, rhs.sqlNode]))
    }

    public static func least<L: SQLExpression, R: SQLExpression>(_ lhs: L, _ rhs: R) -> Expr<L.Value> where L.Value == R.Value {
        Expr(.function("LEAST", [lhs.sqlNode, rhs.sqlNode]))
    }

    public static func least<L: SQLExpression, R: SQLExpression, V: SQLValue>(_ lhs: L, _ rhs: R) -> Expr<V>
    where L.Value == V, R.Value == V? {
        Expr(.function("LEAST", [lhs.sqlNode, rhs.sqlNode]))
    }

    public static func least<L: SQLExpression, R: SQLExpression, V: SQLValue>(_ lhs: L, _ rhs: R) -> Expr<V>
    where L.Value == V?, R.Value == V {
        Expr(.function("LEAST", [lhs.sqlNode, rhs.sqlNode]))
    }

    /// `GREATEST(…)`. PostgreSQL ignores NULL arguments, so a non-null argument makes the result non-null.
    public static func greatest<L: SQLExpression>(_ lhs: L, _ rhs: L.Value.NonNull) -> Expr<L.Value.NonNull> {
        Expr(.function("GREATEST", [lhs.sqlNode, rhs.sqlNode]))
    }

    public static func greatest<R: SQLExpression>(_ lhs: R.Value.NonNull, _ rhs: R) -> Expr<R.Value.NonNull> {
        Expr(.function("GREATEST", [lhs.sqlNode, rhs.sqlNode]))
    }

    public static func greatest<L: SQLExpression, R: SQLExpression>(_ lhs: L, _ rhs: R) -> Expr<L.Value> where L.Value == R.Value {
        Expr(.function("GREATEST", [lhs.sqlNode, rhs.sqlNode]))
    }

    public static func greatest<L: SQLExpression, R: SQLExpression, V: SQLValue>(_ lhs: L, _ rhs: R) -> Expr<V>
    where L.Value == V, R.Value == V? {
        Expr(.function("GREATEST", [lhs.sqlNode, rhs.sqlNode]))
    }

    public static func greatest<L: SQLExpression, R: SQLExpression, V: SQLValue>(_ lhs: L, _ rhs: R) -> Expr<V>
    where L.Value == V?, R.Value == V {
        Expr(.function("GREATEST", [lhs.sqlNode, rhs.sqlNode]))
    }

    // `POWER(base, exponent)` is `double precision` for any mix of the integers, `Float` and `Double`, and `numeric` for
    // two `Decimal`s; `Decimal` takes no other type, as in arithmetic. Either nullable argument makes it nullable. The
    // overloads split on the exponent's nullability, as comparisons do.

    /// `POWER(base, exponent)` in double precision.
    public static func power<B: SQLArgument, E: SQLArgument>(_ base: B, _ exponent: E) -> Expr<B.Value.AsDouble>
    where B.Value: SQLMixedNumeric, E.Value: SQLMixedNumeric, E.Value == E.Value.NonNull {
        Expr(.function("POWER", [base.sqlNode, exponent.sqlNode]))
    }

    public static func power<B: SQLArgument, E: SQLArgument>(_ base: B, _ exponent: E) -> Expr<Double?>
    where B.Value: SQLMixedNumeric, E.Value: SQLMixedNumeric & ExpressibleByNilLiteral {
        Expr(.function("POWER", [base.sqlNode, exponent.sqlNode]))
    }

    /// `POWER(base, exponent)` in `numeric`. A literal exponent is a `Decimal`.
    public static func power<B: SQLExpression>(_ base: B, _ exponent: Decimal) -> Expr<B.Value> where B.Value.NonNull == Decimal {
        Expr(.function("POWER", [base.sqlNode, exponent.sqlNode]))
    }

    public static func power<B: SQLArgument, E: SQLExpression>(_ base: B, _ exponent: E) -> Expr<B.Value>
    where B.Value.NonNull == Decimal, E.Value == Decimal {
        Expr(.function("POWER", [base.sqlNode, exponent.sqlNode]))
    }

    public static func power<B: SQLArgument, E: SQLExpression>(_ base: B, _ exponent: E) -> Expr<Decimal?>
    where B.Value.NonNull == Decimal, E.Value == Decimal? {
        Expr(.function("POWER", [base.sqlNode, exponent.sqlNode]))
    }

    // MARK: Row values
    //
    // One overload per arity, from two to six columns, rather than a parameter pack: when `SQL.row(…).in(…)` is one
    // expression, Swift types an integer literal in the tuples as `Int` before it resolves a pack, so `(7, 8)` would
    // not match `Int64` columns.

    /// Builds a row value for multi-column comparisons: `SQL.row(A.scope, A.key).in([("public", "alpha")])`.
    public static func row<A: SQLExpression, B: SQLExpression>(_ a: A, _ b: B) -> RowValue<A.Value, B.Value> { rowValue(a, b) }

    public static func row<A: SQLExpression, B: SQLExpression, C: SQLExpression>(_ a: A, _ b: B, _ c: C)
        -> RowValue<A.Value, B.Value, C.Value>
    { rowValue(a, b, c) }

    public static func row<A: SQLExpression, B: SQLExpression, C: SQLExpression, D: SQLExpression>(_ a: A, _ b: B, _ c: C, _ d: D)
        -> RowValue<A.Value, B.Value, C.Value, D.Value>
    { rowValue(a, b, c, d) }

    public static func row<A: SQLExpression, B: SQLExpression, C: SQLExpression, D: SQLExpression, E: SQLExpression>(
        _ a: A, _ b: B, _ c: C, _ d: D, _ e: E
    ) -> RowValue<A.Value, B.Value, C.Value, D.Value, E.Value> { rowValue(a, b, c, d, e) }

    public static func row<A: SQLExpression, B: SQLExpression, C: SQLExpression, D: SQLExpression, E: SQLExpression, F: SQLExpression>(
        _ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F
    ) -> RowValue<A.Value, B.Value, C.Value, D.Value, E.Value, F.Value> { rowValue(a, b, c, d, e, f) }

    private static func rowValue<each E: SQLExpression>(_ items: repeat each E) -> RowValue<repeat (each E).Value> {
        var nodes: [SQLNode] = []
        for item in repeat each items { nodes.append(item.sqlNode) }
        return RowValue(nodes: nodes)
    }

    // MARK: Subqueries

    /// `EXISTS (subquery)`, a predicate that is never NULL. Columns of an enclosing query's model inside the subquery
    /// refer to that query's row.
    public static func exists(_ subquery: some SelectQuery) -> Expr<Bool> {
        Expr(.sequence([.raw("EXISTS "), .subquery(subquery.statement)]))
    }

    // MARK: Aggregates

    /// `COUNT(expression)`: counts non-null values.
    public static func count(_ expression: some SQLExpression) -> AggregateExpr<Int64> {
        AggregateExpr(.function("COUNT", [expression.sqlNode]))
    }

    /// `COUNT(*)`.
    public static func countAll() -> AggregateExpr<Int64> { AggregateExpr(.raw("COUNT(*)")) }

    /// `SUM(expression)`. NULL without input rows; integer sums widen like PostgreSQL (`bigint` sums are `numeric`).
    public static func sum<E: SQLExpression>(_ expression: E) -> AggregateExpr<E.Value.NonNull.Sum?> where E.Value.NonNull: SQLSummable {
        AggregateExpr(.function("SUM", [expression.sqlNode]))
    }

    /// `MIN(expression)`. NULL without input rows.
    public static func min<E: SQLExpression>(_ expression: E) -> AggregateExpr<E.Value.NonNull?> {
        AggregateExpr(.function("MIN", [expression.sqlNode]))
    }

    /// `MAX(expression)`. NULL without input rows.
    public static func max<E: SQLExpression>(_ expression: E) -> AggregateExpr<E.Value.NonNull?> {
        AggregateExpr(.function("MAX", [expression.sqlNode]))
    }

    // MARK: Intervals

    public static func interval<E: SQLArgument>(days: E) -> Expr<E.Value.AsInterval> where E.Value.NonNull: SQLNumeric {
        scaledInterval(days, unit: "1 day")
    }

    public static func interval<E: SQLArgument>(hours: E) -> Expr<E.Value.AsInterval> where E.Value.NonNull: SQLNumeric {
        scaledInterval(hours, unit: "1 hour")
    }

    public static func interval<E: SQLArgument>(minutes: E) -> Expr<E.Value.AsInterval> where E.Value.NonNull: SQLNumeric {
        scaledInterval(minutes, unit: "1 minute")
    }

    public static func interval<E: SQLArgument>(seconds: E) -> Expr<E.Value.AsInterval> where E.Value.NonNull: SQLNumeric {
        scaledInterval(seconds, unit: "1 second")
    }

    private static func scaledInterval<E: SQLArgument>(_ amount: E, unit: String) -> Expr<E.Value.AsInterval> {
        Expr(.sequence([.raw("("), amount.sqlNode, .raw(" * INTERVAL '\(unit)')")]))
    }
}

public enum DateTruncUnit: String, Sendable {
    case microseconds, milliseconds, second, minute, hour, day, week, month, quarter, year, decade, century, millennium
}

// MARK: - pgvector
//
// Every distance is `double precision`, nullable when either vector is. The two overloads of each distance split on
// the argument's nullability, so exactly one applies: a required argument keeps the receiver's nullability, and a
// nullable expression makes the distance nullable.

extension SQLExpression where Value.NonNull: PGVectorType {
    /// Euclidean distance, pgvector's `<->`. Index-friendly for `ORDER BY … LIMIT`.
    public func l2Distance(to other: some SQLArgument<Value.NonNull>) -> Expr<Value.AsDouble> {
        Expr(.infix(sqlNode, "<->", other.sqlNode))
    }
    public func l2Distance(to other: any SQLExpression<Value.NonNull?>) -> Expr<Double?> {
        Expr(.infix(sqlNode, "<->", other.sqlNode))
    }

    /// Cosine distance, pgvector's `<=>` (lower is more similar). Index-friendly for `ORDER BY … LIMIT`.
    public func cosineDistance(to other: some SQLArgument<Value.NonNull>) -> Expr<Value.AsDouble> {
        Expr(.infix(sqlNode, "<=>", other.sqlNode))
    }
    public func cosineDistance(to other: any SQLExpression<Value.NonNull?>) -> Expr<Double?> {
        Expr(.infix(sqlNode, "<=>", other.sqlNode))
    }

    /// Negative inner product, pgvector's `<#>` (lower is more similar). Index-friendly for `ORDER BY … LIMIT`.
    public func innerProductDistance(to other: some SQLArgument<Value.NonNull>) -> Expr<Value.AsDouble> {
        Expr(.infix(sqlNode, "<#>", other.sqlNode))
    }
    public func innerProductDistance(to other: any SQLExpression<Value.NonNull?>) -> Expr<Double?> {
        Expr(.infix(sqlNode, "<#>", other.sqlNode))
    }

    /// Taxicab distance, pgvector's `<+>`.
    public func l1Distance(to other: some SQLArgument<Value.NonNull>) -> Expr<Value.AsDouble> {
        Expr(.infix(sqlNode, "<+>", other.sqlNode))
    }
    public func l1Distance(to other: any SQLExpression<Value.NonNull?>) -> Expr<Double?> {
        Expr(.infix(sqlNode, "<+>", other.sqlNode))
    }

    /// The true inner product (higher is more similar). As a function call it can't use ANN indexes.
    public func innerProduct(with other: some SQLArgument<Value.NonNull>) -> Expr<Value.AsDouble> {
        Expr(.function("inner_product", [sqlNode, other.sqlNode]))
    }
    public func innerProduct(with other: any SQLExpression<Value.NonNull?>) -> Expr<Double?> {
        Expr(.function("inner_product", [sqlNode, other.sqlNode]))
    }
}

extension SQLExpression where Value.NonNull: PGBitType {
    /// Hamming distance, pgvector's `<~>`: the number of differing bits. Index-friendly for `ORDER BY … LIMIT`.
    public func hammingDistance(to other: some SQLArgument<Value.NonNull>) -> Expr<Value.AsDouble> {
        Expr(.infix(sqlNode, "<~>", other.sqlNode))
    }
    public func hammingDistance(to other: any SQLExpression<Value.NonNull?>) -> Expr<Double?> {
        Expr(.infix(sqlNode, "<~>", other.sqlNode))
    }

    /// Jaccard distance, pgvector's `<%>`. Index-friendly for `ORDER BY … LIMIT`.
    public func jaccardDistance(to other: some SQLArgument<Value.NonNull>) -> Expr<Value.AsDouble> {
        Expr(.infix(sqlNode, "<%>", other.sqlNode))
    }
    public func jaccardDistance(to other: any SQLExpression<Value.NonNull?>) -> Expr<Double?> {
        Expr(.infix(sqlNode, "<%>", other.sqlNode))
    }
}
