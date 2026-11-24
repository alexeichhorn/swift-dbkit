/// A `SELECT` returning `Row` models: `TodoModel.query().filter(…).all(on: db)`.
///
/// `with(_:)` eager-loads relations and changes `Row` to the model's `Loaded` subclass, so the loaded graph is part of
/// the result type while every row still is the plain model.
public struct Query<Row: Model>: SelectQuery {
    public var statement: SelectStatement
    let plan: LoadPlan<Row>

    init(statement: SelectStatement, plan: LoadPlan<Row>) {
        self.statement = statement
        self.plan = plan
    }

    /// `INNER JOIN` a relation to filter or sort by its columns. Doesn't load it; combine with `distinct()` for
    /// to-many joins.
    public func join<L: RelationLoad>(_ relation: KeyPath<Row.Base.Relations.Type, L>) -> Self where L.Source == Row.Base {
        updating { $0.joins.append(.relation(Row.Base.Relations.self[keyPath: relation].relation, .inner)) }
    }

    public func leftJoin<L: RelationLoad>(_ relation: KeyPath<Row.Base.Relations.Type, L>) -> Self where L.Source == Row.Base {
        updating { $0.joins.append(.relation(Row.Base.Relations.self[keyPath: relation].relation, .left)) }
    }

    /// Locks the selected rows: `SELECT … FOR UPDATE`. Use inside a transaction. PostgreSQL rejects locking
    /// together with `DISTINCT` or `GROUP BY`.
    public func forUpdate(_ waiting: RowLock = .wait) -> Self {
        updating { $0.lock = waiting }
    }

    /// Switches to a projection of the given expressions, decoded as a typed tuple:
    /// `.select(SaleModel.region, SQL.sum(SaleModel.amount))` returns `(String, Decimal?)` rows.
    public func select<each E: SQLExpression>(_ expressions: repeat each E) -> Projection<repeat (each E).Value> {
        var items: [SelectItem] = []
        for expression in repeat each expressions { items.append(SelectItem(node: expression.sqlNode, alias: nil)) }
        return Projection(statement: updating { $0.items = items }.statement)
    }

    /// Switches to a projection of named expressions, decodable as a tuple or into a `Decodable` type whose
    /// properties match the aliases.
    public func select<each V: SQLType>(_ expressions: repeat Aliased<each V>) -> Projection<repeat each V> {
        var items: [SelectItem] = []
        for expression in repeat each expressions { items.append(SelectItem(node: expression.node, alias: expression.alias)) }
        return Projection(statement: updating { $0.items = items }.statement)
    }

    /// Switches to a projection into a `@Projection` type, which names every result column in code:
    /// `.select(Totals.columns(saleCount: SQL.count(SaleModel.id), newest: SQL.max(SaleModel.createdAt)))`.
    public func select<T>(_ columns: ProjectionColumns<T>) -> ProjectionQuery<T> {
        let items = columns.nodes.map { SelectItem(node: $0, alias: nil) }
        return ProjectionQuery(statement: updating { $0.items = items }.statement, decode: columns.decode)
    }

    public func render() -> RenderedSQL {
        let renderer = SQLRenderer()
        let sql = renderer.renderSelect(statement, eagerJoins: plan.joins)
        return RenderedSQL(sql: sql, binds: renderer.binds)
    }

    public func all(on executor: some DatabaseExecutor) async throws -> [Row] {
        let nodes = try await RawNode.load(render(), model: Row.Base.self, joins: plan.joins, on: executor)
        return try await plan.build(nodes, executor)
    }

    /// The first row (`LIMIT 1`). With a joined to-many load, the limit applies to joined rows, so use `.selectIn`.
    public func first(on executor: some DatabaseExecutor) async throws -> Row? {
        try await limit(1).all(on: executor).first
    }

    /// Fetches one page; `page` is 1-based. Order the query for stable pages. `total` counts each row once, but with a
    /// joined to-many load the page's limit applies to joined rows, so use `.selectIn`.
    public func paginate(page: Int, perPage: Int, on executor: some DatabaseExecutor) async throws -> Page<Row> {
        precondition(page >= 1 && perPage >= 1, "page and perPage must be positive")
        let total = try await count(on: executor)
        let items = try await limit(perPage).offset((page - 1) * perPage).all(on: executor)
        return Page(items: items, page: page, perPage: perPage, total: total)
    }
}

extension Query: ModelRowsQuery {
    var eagerJoins: [JoinedLoad] { plan.joins }
    var keyColumns: [String] { Row.Base.schema.primaryKey }
}

extension Query where Row == Row.Base {
    init() {
        self.init(statement: SelectStatement(table: Row.schema.tableName), plan: .base)
    }

    /// Eager-loads a relation: `.with(\.todos)` turns `UserModel` rows into `UserModel.Loaded<…, [TodoModel]>`.
    public func with<L: RelationLoad>(_ relation: KeyPath<Row.Relations.Type, L>, _ strategy: LoadStrategy = .selectIn) -> Query<L.Output>
    where L.Source == Row {
        Query<L.Output>(statement: statement, plan: plan.adding(Row.Relations.self[keyPath: relation], strategy))
    }

    /// Eager-loads a relation with nested loads for its rows: `.with(\.todos) { $0.with(\.tags) }`.
    public func with<L: RelationLoad, Nested: RelationLoad>(
        _ relation: KeyPath<Row.Relations.Type, L>,
        _ strategy: LoadStrategy = .selectIn,
        _ nested: (L) -> Nested
    ) -> Query<Nested.Output> where Nested.Source == Row {
        Query<Nested.Output>(statement: statement, plan: plan.adding(nested(Row.Relations.self[keyPath: relation]), strategy))
    }

    /// Streams rows through a server-side cursor instead of collecting an array. Eager loading isn't supported.
    ///
    /// Rows are fetched 1,000 at a time, and leaving the loop stops fetching. From its first row until it ends or
    /// is dropped, the stream holds a pooled connection and its own transaction on it.
    public func stream(on database: Database) async throws -> RowStream<Row> {
        RowStream(query: try database.postgresQuery(render()), executor: database) {
            try Row.decodeBase(from: RowReader(row: $0, prefix: ""))
        }
    }

    /// Streams rows like ``stream(on:)-(Database)``, on the transaction's connection. The transaction stays open
    /// when the stream ends.
    public func stream(on transaction: Transaction) async throws -> RowStream<Row> {
        RowStream(query: try transaction.postgresQuery(render()), executor: transaction) {
            try Row.decodeBase(from: RowReader(row: $0, prefix: ""))
        }
    }
}

extension Query where Row: LoadedModel {
    /// Eager-loads another relation, keeping the ones already loaded.
    public func with<L: RelationLoad>(_ relation: KeyPath<Row.LoadedRelations.Type, L>, _ strategy: LoadStrategy = .selectIn)
        -> Query<L.Output> where L.Source == Row
    {
        Query<L.Output>(statement: statement, plan: plan.adding(Row.LoadedRelations.self[keyPath: relation], strategy))
    }

    public func with<L: RelationLoad, Nested: RelationLoad>(
        _ relation: KeyPath<Row.LoadedRelations.Type, L>,
        _ strategy: LoadStrategy = .selectIn,
        _ nested: (L) -> Nested
    ) -> Query<Nested.Output> where Nested.Source == Row {
        Query<Nested.Output>(statement: statement, plan: plan.adding(nested(Row.LoadedRelations.self[keyPath: relation]), strategy))
    }
}
