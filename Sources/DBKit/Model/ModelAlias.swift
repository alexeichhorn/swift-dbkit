/// A model's table under another name, created by `Model.as(_:)`. A subquery on the outer query's own table needs it
/// to tell the two rows apart:
///
/// ```swift
/// let reports = EmployeeModel.as("reports")
/// EmployeeModel.query().whereExists(reports.query().filter(reports.managerID == EmployeeModel.id))
/// ```
@dynamicMemberLookup
public struct ModelAlias<Row: Model>: Sendable where Row.Base == Row {
    let name: String

    /// The column qualified by this alias: `reports.managerID` is `"reports"."manager_id"`.
    public subscript<V: SQLType>(dynamicMember column: KeyPath<Row.Type, Column<Row, V>>) -> Expr<V> {
        Expr(.column(ColumnReference(table: name, name: Row.self[keyPath: column].name, path: [])))
    }

    /// Starts a `SELECT` from `"table" AS "alias"`.
    public func query() -> Query<Row> {
        var query = Row.query()
        query.statement.alias = name
        return query
    }
}

extension Model where Base == Self {
    /// This model's table under `alias`, which is quoted like any identifier.
    public static func `as`(_ alias: String) -> ModelAlias<Self> { ModelAlias(name: alias) }
}
