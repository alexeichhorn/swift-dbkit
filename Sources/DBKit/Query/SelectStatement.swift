/// The untyped parts of a `SELECT`.
public struct SelectStatement: Sendable {
    var table: String
    var distinct = false
    var filters: [SQLNode] = []
    var orderBy: [OrderBy] = []
    var limit: Int?
    var offset: Int?

    init(table: String) {
        self.table = table
    }
}

/// Renders statements to SQL, numbering bind placeholders.
final class SQLRenderer {
    private(set) var binds: [Bind] = []

    func render(_ node: SQLNode) -> String {
        switch node {
        case .column(let column):
            return "\(quoted(column.table)).\(quoted(column.name))"
        case .bind(let bind):
            binds.append(bind)
            return "$\(binds.count)"
        case .raw(let sql):
            return sql
        case .sequence(let nodes):
            return nodes.map { render($0) }.joined()
        }
    }

    func renderSelect(_ statement: SelectStatement) -> String {
        var clauses: [String] = []
        if !statement.filters.isEmpty {
            clauses.append("WHERE " + statement.filters.map { render($0) }.joined(separator: " AND "))
        }
        if !statement.orderBy.isEmpty {
            let orders = statement.orderBy.map { render($0.node) + ($0.descending ? " DESC" : " ASC") }
            clauses.append("ORDER BY " + orders.joined(separator: ", "))
        }
        if let limit = statement.limit { clauses.append("LIMIT \(limit)") }
        if let offset = statement.offset { clauses.append("OFFSET \(offset)") }

        let head = "SELECT \(statement.distinct ? "DISTINCT " : "")\(quoted(statement.table)).* FROM \(quoted(statement.table))"
        return ([head] + clauses).joined(separator: " ")
    }
}

/// Quotes an SQL identifier.
func quoted(_ identifier: String) -> String {
    "\"" + identifier.replacing("\"", with: "\"\"") + "\""
}
