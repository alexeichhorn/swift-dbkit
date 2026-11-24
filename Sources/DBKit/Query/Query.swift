/// A `SELECT` returning `Row` models: `TodoModel.query().filter(…).all(on: db)`.
public struct Query<Row: Model>: SelectQuery {
    public var statement: SelectStatement

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
