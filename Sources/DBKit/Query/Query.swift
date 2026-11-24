/// A `SELECT` returning `Row` models: `TodoModel.query().filter(…).all(on: db)`.
public struct Query<Row: Model>: SelectQuery {
    public var statement: SelectStatement

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
}

extension Query where Row == Row.Base {
    init() {
        self.statement = SelectStatement(table: Row.schema.table)
    }

    public func all(on executor: some DatabaseExecutor) async throws -> [Row] {
        try await executor.rows(render()) { try Row.decodeBase(from: RowReader(row: $0)) }
    }

    /// The first row (`LIMIT 1`).
    public func first(on executor: some DatabaseExecutor) async throws -> Row? {
        try await limit(1).all(on: executor).first
    }
}
