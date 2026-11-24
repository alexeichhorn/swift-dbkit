/// An `INSERT` of one or more rows, created by `Model.insert(_:)`.
public struct InsertQuery<Row: Model>: Sendable where Row.Base == Row {
    let rows: [[ColumnValue]]

    /// Returns the inserted rows (`RETURNING *`).
    public func returningAll() -> Returning<Row> { Returning(statement: statement) }

    /// Runs the insert and returns the number of inserted rows.
    @discardableResult
    public func execute(on executor: some DatabaseExecutor) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        return try await executor.execute(render())
    }

    public func render() -> RenderedSQL {
        statement.render(returningAll: false)
    }

    var statement: MutationStatement {
        MutationStatement { renderer in
            let columns = rows.first?.map(\.column) ?? []
            let values = rows.map { row in "(" + row.map { renderer.render($0.node) }.joined(separator: ", ") + ")" }
            var sql = "INSERT INTO \(quoted(Row.schema.table)) (\(columns.map(quoted).joined(separator: ", "))) VALUES "
            sql += values.joined(separator: ", ")
            return sql
        }
    }
}

/// An `UPDATE`, created by `Model.update()`. Without a filter it updates every row.
public struct UpdateQuery<Row: Model>: Sendable where Row.Base == Row {
    var assignments: [ColumnValue] = []
    var filters: [SQLNode] = []

    /// Sets a column to a value; `nil` is accepted only for nullable columns.
    public func set<V: SQLType>(_ column: Column<Row, V>, to value: V) -> Self {
        setting(column.name, value.sqlNode)
    }

    public func filter<P: SQLExpression>(_ predicate: P) -> Self where P.Value.NonNull == Bool {
        filtered(predicate.sqlNode)
    }

    public func returningAll() -> Returning<Row> { Returning(statement: statement) }

    /// Runs the update and returns the number of updated rows.
    @discardableResult
    public func execute(on executor: some DatabaseExecutor) async throws -> Int {
        try await executor.execute(render())
    }

    public func render() -> RenderedSQL {
        statement.render(returningAll: false)
    }

    func filtered(_ node: SQLNode) -> Self {
        var copy = self
        copy.filters.append(node)
        return copy
    }

    private func setting(_ column: String, _ node: SQLNode) -> Self {
        var copy = self
        copy.assignments.append(ColumnValue(column: column, node: node))
        return copy
    }

    var statement: MutationStatement {
        precondition(!assignments.isEmpty, "an UPDATE needs at least one set(_:to:)")
        return MutationStatement { renderer in
            let sets = assignments.map { "\(quoted($0.column)) = \(renderer.render($0.node))" }
            var sql = "UPDATE \(quoted(Row.schema.table)) SET \(sets.joined(separator: ", "))"
            if !filters.isEmpty { sql += " WHERE " + filters.map { renderer.render($0) }.joined(separator: " AND ") }
            return sql
        }
    }
}

/// A `DELETE`, created by `Model.delete()`. Without a filter it deletes every row.
public struct DeleteQuery<Row: Model>: Sendable where Row.Base == Row {
    var filters: [SQLNode] = []

    public func filter<P: SQLExpression>(_ predicate: P) -> Self where P.Value.NonNull == Bool {
        filtered(predicate.sqlNode)
    }

    public func returningAll() -> Returning<Row> { Returning(statement: statement) }

    /// Runs the delete and returns the number of deleted rows.
    @discardableResult
    public func execute(on executor: some DatabaseExecutor) async throws -> Int {
        try await executor.execute(render())
    }

    public func render() -> RenderedSQL {
        statement.render(returningAll: false)
    }

    func filtered(_ node: SQLNode) -> Self {
        var copy = self
        copy.filters.append(node)
        return copy
    }

    var statement: MutationStatement {
        MutationStatement { renderer in
            var sql = "DELETE FROM \(quoted(Row.schema.table))"
            if !filters.isEmpty { sql += " WHERE " + filters.map { renderer.render($0) }.joined(separator: " AND ") }
            return sql
        }
    }
}

/// A mutation with `RETURNING *`, decoding the affected rows.
public struct Returning<Row: Model>: Sendable where Row.Base == Row {
    let statement: MutationStatement

    public func all(on executor: some DatabaseExecutor) async throws -> [Row] {
        try await executor.rows(render()) { try Row.decodeBase(from: RowReader(row: $0)) }
    }

    /// The first affected row, or `nil` when none was affected.
    public func first(on executor: some DatabaseExecutor) async throws -> Row? {
        try await all(on: executor).first
    }

    public func render() -> RenderedSQL {
        statement.render(returningAll: true)
    }
}

/// Renders a mutation.
struct MutationStatement: Sendable {
    let body: @Sendable (SQLRenderer) -> String

    func render(returningAll: Bool) -> RenderedSQL {
        let renderer = SQLRenderer()
        let sql = body(renderer) + (returningAll ? " RETURNING *" : "")
        return RenderedSQL(sql: sql, binds: renderer.binds)
    }
}
