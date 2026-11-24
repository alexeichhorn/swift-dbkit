extension SQLExpression {
    public var isNull: Expr<Bool> { Expr(.sequence([sqlNode, .raw(" IS NULL")])) }
    public var isNotNull: Expr<Bool> { Expr(.sequence([sqlNode, .raw(" IS NOT NULL")])) }

    /// `IN (…)`; an empty list matches nothing.
    public func `in`(_ values: [Value]) -> Expr<Value.AsBool> {
        values.isEmpty ? Expr(.raw("FALSE")) : Expr(.sequence([sqlNode, .raw(" IN "), .list(values.map(\.sqlNode))]))
    }

    /// `NOT IN (…)`; an empty list matches everything.
    public func notIn(_ values: [Value]) -> Expr<Value.AsBool> {
        values.isEmpty ? Expr(.raw("TRUE")) : Expr(.sequence([sqlNode, .raw(" NOT IN "), .list(values.map(\.sqlNode))]))
    }

    public func between(_ lower: Value, _ upper: Value) -> Expr<Value.AsBool> {
        Expr(.sequence([sqlNode, .raw(" BETWEEN "), lower.sqlNode, .raw(" AND "), upper.sqlNode]))
    }
}

extension SQLExpression where Value.NonNull == String {
    public func like(_ pattern: some SQLArgument<String>) -> Expr<Value.AsBool> {
        Expr(.infix(sqlNode, "LIKE", pattern.sqlNode, parenthesized: false))
    }

    public func ilike(_ pattern: some SQLArgument<String>) -> Expr<Value.AsBool> {
        Expr(.infix(sqlNode, "ILIKE", pattern.sqlNode, parenthesized: false))
    }
}

/// Nullable text also matches an optional pattern, as `LIKE NULL` when it is `nil`.
extension SQLExpression where Value == String? {
    public func like(_ pattern: String?) -> Expr<Bool?> {
        Expr(.infix(sqlNode, "LIKE", pattern.sqlNode, parenthesized: false))
    }

    public func ilike(_ pattern: String?) -> Expr<Bool?> {
        Expr(.infix(sqlNode, "ILIKE", pattern.sqlNode, parenthesized: false))
    }
}
