/// An `INSERT` of one or more rows, created by `Model.insert(_:)`.
public struct InsertQuery<Row: Model>: Sendable where Row.Base == Row {
    let rows: [[ColumnValue]]
    var conflict: SQLNode?

    /// `ON CONFLICT (target) DO NOTHING`. Without columns, any unique violation is ignored.
    public func onConflictDoNothing<each V: SQLType>(_ target: repeat Column<Row, each V>) -> Self {
        var copy = self
        copy.conflict = .raw("ON CONFLICT \(conflictTarget(repeat each target))DO NOTHING")
        return copy
    }

    /// `ON CONFLICT (target) DO UPDATE SET column = EXCLUDED.column` for each column in `update`.
    public func onConflict<each T: SQLType, each U: SQLType>(
        _ target: repeat Column<Row, each T>, doUpdate update: repeat Column<Row, each U>
    )
        -> Self
    {
        var assignments: [String] = []
        for column in repeat each update { assignments.append("\(quoted(column.name)) = EXCLUDED.\(quoted(column.name))") }
        var copy = self
        copy.conflict = .raw("ON CONFLICT \(conflictTarget(repeat each target))DO UPDATE SET \(assignments.joined(separator: ", "))")
        return copy
    }

    /// The same upsert with the columns as tuples, so a column list can be kept in a constant and reused:
    /// `let updates = (UserModel.name, UserModel.region)`, then `.onConflict(UserModel.email, doUpdate: updates)`.
    @_disfavoredOverload
    public func onConflict<each T: SQLType, each U: SQLType>(
        _ target: (repeat Column<Row, each T>), doUpdate update: (repeat Column<Row, each U>)
    ) -> Self {
        onConflict(repeat each target, doUpdate: repeat each update)
    }

    /// Returns the inserted rows (`RETURNING *`).
    public func returningAll() -> Returning<Row> { Returning(statement: statement) }

    /// Runs the insert and returns the number of inserted (or upserted) rows.
    @discardableResult
    public func execute(on executor: some DatabaseExecutor) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        return try await executor.execute(render())
    }

    public func render() -> RenderedSQL {
        statement.render(returningAll: false)
    }

    var statement: MutationStatement {
        MutationStatement(table: Row.schema.tableName) { renderer, scope in
            let columns = rows.first?.map(\.column) ?? []
            let values = rows.map { row in "(" + row.map { renderer.render($0.node, in: scope) }.joined(separator: ", ") + ")" }
            var sql = "INSERT INTO \(Row.schema.tableName.sql) (\(columns.map(quoted).joined(separator: ", "))) VALUES "
            sql += values.joined(separator: ", ")
            if let conflict { sql += " " + renderer.render(conflict, in: scope) }
            return sql
        }
    }

    private func conflictTarget<each V>(_ target: repeat Column<Row, each V>) -> String {
        var columns: [String] = []
        for column in repeat each target { columns.append(quoted(column.name)) }
        return columns.isEmpty ? "" : "(\(columns.joined(separator: ", "))) "
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

    /// Sets a column to an expression, e.g. `.set(Job.attempts, to: Job.attempts + 1)`.
    public func set<V: SQLType, E: SQLExpression>(_ column: Column<Row, V>, to expression: E) -> Self where E.Value == V {
        setting(column.name, expression.sqlNode)
    }

    public func set<W: SQLValue, E: SQLExpression>(_ column: Column<Row, W?>, to expression: E) -> Self where E.Value == W {
        setting(column.name, expression.sqlNode)
    }

    public func filter<P: SQLExpression>(_ predicate: P) -> Self where P.Value.NonNull == Bool {
        filtered(predicate.sqlNode)
    }

    public func whereExists(_ subquery: some SelectQuery) -> Self {
        filtered(.sequence([.raw("EXISTS "), .subquery(subquery.statement)]))
    }

    public func whereNotExists(_ subquery: some SelectQuery) -> Self {
        filtered(.sequence([.raw("NOT EXISTS "), .subquery(subquery.statement)]))
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
        return MutationStatement(table: Row.schema.tableName) { renderer, scope in
            let sets = assignments.map { "\(quoted($0.column)) = \(renderer.render($0.node, in: scope))" }
            var sql = "UPDATE \(Row.schema.tableName.sql) SET \(sets.joined(separator: ", "))"
            if !filters.isEmpty { sql += " WHERE " + filters.map { renderer.render($0, in: scope) }.joined(separator: " AND ") }
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

    public func whereExists(_ subquery: some SelectQuery) -> Self {
        filtered(.sequence([.raw("EXISTS "), .subquery(subquery.statement)]))
    }

    public func whereNotExists(_ subquery: some SelectQuery) -> Self {
        filtered(.sequence([.raw("NOT EXISTS "), .subquery(subquery.statement)]))
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
        MutationStatement(table: Row.schema.tableName) { renderer, scope in
            var sql = "DELETE FROM \(Row.schema.tableName.sql)"
            if !filters.isEmpty { sql += " WHERE " + filters.map { renderer.render($0, in: scope) }.joined(separator: " AND ") }
            return sql
        }
    }
}

/// A mutation with `RETURNING *`, decoding the affected rows.
public struct Returning<Row: Model>: Sendable where Row.Base == Row {
    let statement: MutationStatement

    public func all(on executor: some DatabaseExecutor) async throws -> [Row] {
        try await executor.rows(render()) { try Row.decodeBase(from: RowReader(row: $0, prefix: "")) }
    }

    /// The first affected row, or `nil` when none was affected (e.g. after `onConflictDoNothing`).
    public func first(on executor: some DatabaseExecutor) async throws -> Row? {
        try await all(on: executor).first
    }

    public func render() -> RenderedSQL {
        statement.render(returningAll: true)
    }
}

/// Renders a mutation. Relation paths aren't supported because mutations have no joins; the target table is the
/// enclosing scope of the mutation's subqueries.
struct MutationStatement: Sendable {
    let table: TableName
    let body: @Sendable (SQLRenderer, JoinScope) -> String

    func render(returningAll: Bool) -> RenderedSQL {
        let renderer = SQLRenderer()
        let sql = body(renderer, JoinScope(base: table)) + (returningAll ? " RETURNING *" : "")
        return RenderedSQL(sql: sql, binds: renderer.binds)
    }
}
