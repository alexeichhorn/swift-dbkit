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

    /// Switches to a projection of the given expressions, decoded as a typed tuple:
    /// `.select(UserModel.id, UserModel.email)` returns `(Int64, String?)` rows.
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
    /// `.select(Contact.columns(name: UserModel.name, email: UserModel.email))`.
    public func select<T>(_ columns: ProjectionColumns<T>) -> ProjectionQuery<T> {
        let items = columns.nodes.map { SelectItem(node: $0, alias: nil) }
        return ProjectionQuery(statement: updating { $0.items = items }.statement, decode: columns.decode)
    }

    public func render() -> RenderedSQL {
        let renderer = SQLRenderer()
        let sql = renderer.renderSelect(statement)
        return RenderedSQL(sql: sql, binds: renderer.binds)
    }

    public func all(on executor: some DatabaseExecutor) async throws -> [Row] {
        let nodes = try await RawNode.load(render(), model: Row.Base.self, on: executor)
        return try await plan.build(nodes, executor)
    }

    /// The first row (`LIMIT 1`).
    public func first(on executor: some DatabaseExecutor) async throws -> Row? {
        try await limit(1).all(on: executor).first
    }
}

extension Query where Row == Row.Base {
    init() {
        self.init(statement: SelectStatement(table: Row.schema.table), plan: .base)
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
