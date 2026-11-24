extension SQLExpression {
    public var isNull: Expr<Bool> { Expr(.nullCheck(sqlNode, "IS NULL")) }
    public var isNotNull: Expr<Bool> { Expr(.nullCheck(sqlNode, "IS NOT NULL")) }

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

    public func between<Lower: SQLExpression, Upper: SQLExpression>(_ lower: Lower, _ upper: Upper) -> Expr<Value.AsBool>
    where Lower.Value == Value.NonNull, Upper.Value == Value.NonNull {
        Expr(.sequence([sqlNode, .raw(" BETWEEN "), lower.sqlNode, .raw(" AND "), upper.sqlNode]))
    }

    /// A nullable bound makes the result nullable. Required bounds also match here, but the overload above is the more
    /// specific one.
    public func between<Lower: SQLExpression, Upper: SQLExpression>(_ lower: Lower, _ upper: Upper) -> Expr<Bool?>
    where Lower.Value.NonNull == Value.NonNull, Upper.Value.NonNull == Value.NonNull {
        Expr(.sequence([sqlNode, .raw(" BETWEEN "), lower.sqlNode, .raw(" AND "), upper.sqlNode]))
    }

    /// NULL-safe inequality: `IS DISTINCT FROM`. Accepts `nil` for nullable expressions.
    public func isDistinct(from value: Value) -> Expr<Bool> {
        Expr(.comparison(sqlNode, "IS DISTINCT FROM", value.sqlNode))
    }

    public func isDistinct<Other: SQLExpression>(from other: Other) -> Expr<Bool> where Other.Value.NonNull == Value.NonNull {
        Expr(.comparison(sqlNode, "IS DISTINCT FROM", other.sqlNode))
    }

    /// NULL-safe equality: `IS NOT DISTINCT FROM`. Accepts `nil` for nullable expressions.
    public func isNotDistinct(from value: Value) -> Expr<Bool> {
        Expr(.comparison(sqlNode, "IS NOT DISTINCT FROM", value.sqlNode))
    }

    public func isNotDistinct<Other: SQLExpression>(from other: Other) -> Expr<Bool> where Other.Value.NonNull == Value.NonNull {
        Expr(.comparison(sqlNode, "IS NOT DISTINCT FROM", other.sqlNode))
    }
}

// MARK: - Casts
//
// `cast(to:)` compiles to `CAST(… AS type)`, keeps the expression's nullability, and accepts only casts PostgreSQL
// has: between numeric types, from and to `String` for the `SQLTextCastable` types, and from a `SQLCastPartner`'s
// partner. Every overload takes the target as a generic type, so a cast PostgreSQL lacks fails a requirement of
// `cast(to:)` instead of being reported as the wrong target argument.

extension SQLExpression {
    public func cast<T: SQLNumeric>(to type: T.Type) -> Expr<T> where Value: SQLNumeric { casting(to: T.self) }

    public func cast<T: SQLNumeric>(to type: T.Type) -> Expr<T?> where Value.NonNull: SQLNumeric { casting(to: T.self) }

    /// `T` is `String`, the only `StringProtocol` that is a `SQLValue`. Disfavored so that a cast from `String` to
    /// `String` takes the overloads from `String`.
    @_disfavoredOverload
    public func cast<T: StringProtocol & SQLValue>(to type: T.Type) -> Expr<Value.AsString> where Value.NonNull: SQLTextCastable {
        casting(to: T.self)
    }

    public func cast<T: SQLCastPartner>(to type: T.Type) -> Expr<T> where Value == T.CastPartner { casting(to: T.self) }

    public func cast<T: SQLCastPartner>(to type: T.Type) -> Expr<T?> where Value == T.CastPartner? { casting(to: T.self) }

    private func casting<T: SQLValue, Result>(to type: T.Type) -> Expr<Result> {
        Expr(.sequence([.raw("CAST("), sqlNode, .raw(" AS \(T.sqlTypeName))")]))
    }
}

extension SQLExpression where Value == String {
    public func cast<T: SQLTextCastable>(to type: T.Type) -> Expr<T> { casting(to: T.self) }
}

extension SQLExpression where Value == String? {
    public func cast<T: SQLTextCastable>(to type: T.Type) -> Expr<T?> { casting(to: T.self) }
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
