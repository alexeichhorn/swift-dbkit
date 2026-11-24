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
        updating { $0.joins.append(.table(Other.schema.tableName, on: condition.sqlNode, .inner)) }
    }

    public func leftJoin<Other: Model, P: SQLExpression>(_ other: Other.Type, on condition: P) -> Self where P.Value.NonNull == Bool {
        updating { $0.joins.append(.table(Other.schema.tableName, on: condition.sqlNode, .left)) }
    }

    func filtered(_ node: SQLNode) -> Self { updating { $0.filters.append(node) } }

    func updating(_ change: (inout SelectStatement) -> Void) -> Self {
        var copy = self
        change(&copy.statement)
        return copy
    }

    /// The number of rows the query returns, ignoring its ordering, limit, offset and lock. A model query counts each
    /// of its rows once, however many rows its joins match.
    public func count(on executor: some DatabaseExecutor) async throws -> Int {
        try await scalar("SELECT COUNT(*) FROM", "AS \"count\"", countsKeys: true, as: Int64.self, on: executor).map(Int.init) ?? 0
    }

    /// Whether the query returns any row, ignoring its ordering, limit, offset and lock.
    public func exists(on executor: some DatabaseExecutor) async throws -> Bool {
        try await scalar("SELECT EXISTS", "", countsKeys: false, as: Bool.self, on: executor) ?? false
    }

    private func scalar<T: SQLValue>(
        _ prefix: String, _ suffix: String, countsKeys: Bool, as type: T.Type, on executor: some DatabaseExecutor
    ) async throws -> T? {
        let renderer = SQLRenderer()
        // A cast rather than a `Query` overload, so a count through `some SelectQuery` keeps the eager joins too.
        let model = self as? any ModelRowsQuery
        let columns: ModelColumns = if countsKeys, let model { .distinctKeysWhenJoined(model.keyColumns) } else { .table }
        let inner = renderer.renderCounted(statement, eagerJoins: model?.eagerJoins ?? [], modelColumns: columns)
        let sql = "\(prefix) (\(inner))" + (suffix.isEmpty ? "" : " \(suffix)")
        return try await executor.rows(RenderedSQL(sql: sql, binds: renderer.binds)) { try $0[0].decode(T.self) }.first
    }
}

/// A query of models, whose `count` and `exists` keep the joins of its eager loads and whose `count` needs its keys.
protocol ModelRowsQuery {
    var eagerJoins: [JoinedLoad] { get }
    var keyColumns: [String] { get }
}

/// One page of results from `paginate`.
public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    /// The 1-based page number.
    public let page: Int
    public let perPage: Int
    /// The number of rows across all pages.
    public let total: Int

    public var totalPages: Int { perPage > 0 ? (total + perPage - 1) / perPage : 0 }
}
