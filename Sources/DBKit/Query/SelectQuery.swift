/// Builder methods shared by model queries (``Query``) and projections (``Projection``).
public protocol SelectQuery: Sendable {
    var statement: SelectStatement { get set }
}

extension SelectQuery {
    /// Adds a `WHERE` predicate; several filters are combined with `AND`.
    public func filter<P: SQLExpression>(_ predicate: P) -> Self where P.Value.NonNull == Bool {
        filtered(predicate.sqlNode)
    }

    /// Adds a dynamically built condition; an empty condition adds nothing.
    public func filter(_ condition: Condition) -> Self {
        guard let predicate = condition.predicate else { return self }
        return filter(predicate)
    }

    /// `WHERE EXISTS (subquery)`. Columns of this query's model inside the subquery correlate with the outer row.
    public func whereExists(_ subquery: some SelectQuery) -> Self {
        filtered(.sequence([.raw("EXISTS "), .subquery(subquery.statement)]))
    }

    public func whereNotExists(_ subquery: some SelectQuery) -> Self {
        filtered(.sequence([.raw("NOT EXISTS "), .subquery(subquery.statement)]))
    }

    public func orderBy(_ orders: OrderBy...) -> Self {
        updating { $0.orderBy += orders }
    }

    public func limit(_ count: Int) -> Self { updating { $0.limit = count } }

    public func offset(_ count: Int) -> Self { updating { $0.offset = count } }

    public func distinct() -> Self { updating { $0.distinct = true } }

    public func groupBy<each E: SQLExpression>(_ expressions: repeat each E) -> Self {
        var nodes: [SQLNode] = []
        for expression in repeat each expressions { nodes.append(expression.sqlNode) }
        return updating { $0.groupBy += nodes }
    }

    /// Filters groups after aggregation.
    public func having<P: SQLExpression>(_ predicate: P) -> Self where P.Value.NonNull == Bool {
        updating { $0.having.append(predicate.sqlNode) }
    }

    /// `JOIN other ON condition`, for tables without a declared relation.
    public func join<Other: Model, P: SQLExpression>(_ other: Other.Type, on condition: P) -> Self where P.Value.NonNull == Bool {
        updating { $0.joins.append(.table(Other.schema.table, on: condition.sqlNode, .inner)) }
    }

    public func leftJoin<Other: Model, P: SQLExpression>(_ other: Other.Type, on condition: P) -> Self where P.Value.NonNull == Bool {
        updating { $0.joins.append(.table(Other.schema.table, on: condition.sqlNode, .left)) }
    }

    func filtered(_ node: SQLNode) -> Self { updating { $0.filters.append(node) } }

    func updating(_ change: (inout SelectStatement) -> Void) -> Self {
        var copy = self
        change(&copy.statement)
        return copy
    }
}
