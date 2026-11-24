/// A `SELECT` returning `Row` models: `TodoModel.query().filter(…)`.
public struct Query<Row: Model>: SelectQuery {
    public var statement: SelectStatement

    init() {
        self.statement = SelectStatement(table: Row.schema.table)
    }

    public func render() -> RenderedSQL {
        let renderer = SQLRenderer()
        let sql = renderer.renderSelect(statement)
        return RenderedSQL(sql: sql, binds: renderer.binds)
    }
}
