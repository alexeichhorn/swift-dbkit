/// Builder methods shared by `SELECT` queries.
public protocol SelectQuery: Sendable {
    var statement: SelectStatement { get set }
}

extension SelectQuery {
    /// Adds a `WHERE` predicate; several filters are combined with `AND`.
    public func filter<P: SQLExpression>(_ predicate: P) -> Self where P.Value.NonNull == Bool {
        filtered(predicate.sqlNode)
    }

    public func orderBy(_ orders: OrderBy...) -> Self {
        updating { $0.orderBy += orders }
    }

    public func limit(_ count: Int) -> Self { updating { $0.limit = count } }

    public func offset(_ count: Int) -> Self { updating { $0.offset = count } }

    public func distinct() -> Self { updating { $0.distinct = true } }

    func filtered(_ node: SQLNode) -> Self { updating { $0.filters.append(node) } }

    func updating(_ change: (inout SelectStatement) -> Void) -> Self {
        var copy = self
        change(&copy.statement)
        return copy
    }
}
