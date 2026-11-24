/// Typed SQL functions. Results keep the nullability of their inputs where PostgreSQL propagates NULL.
public enum SQL {
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
