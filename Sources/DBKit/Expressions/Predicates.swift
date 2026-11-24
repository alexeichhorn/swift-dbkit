extension SQLExpression {
    /// `IN (…)`; an empty list matches nothing.
    public func `in`(_ values: [Value.NonNull]) -> Expr<Bool> {
        values.isEmpty ? Expr(.raw("FALSE")) : Expr(.sequence([sqlNode, .raw(" IN "), .list(values.map(\.sqlNode))]))
    }

    /// `NOT IN (…)`; an empty list matches everything.
    public func notIn(_ values: [Value.NonNull]) -> Expr<Bool> {
        values.isEmpty ? Expr(.raw("TRUE")) : Expr(.sequence([sqlNode, .raw(" NOT IN "), .list(values.map(\.sqlNode))]))
    }

    public func between(_ lower: Value.NonNull, _ upper: Value.NonNull) -> Expr<Bool> {
        Expr(.sequence([sqlNode, .raw(" BETWEEN "), lower.sqlNode, .raw(" AND "), upper.sqlNode]))
    }
}

extension SQLExpression where Value.NonNull == String {
    public func like(_ pattern: some SQLArgument<String>) -> Expr<Bool> {
        Expr(.infix(sqlNode, "LIKE", pattern.sqlNode, parenthesized: false))
    }

    public func ilike(_ pattern: some SQLArgument<String>) -> Expr<Bool> {
        Expr(.infix(sqlNode, "ILIKE", pattern.sqlNode, parenthesized: false))
    }
}
