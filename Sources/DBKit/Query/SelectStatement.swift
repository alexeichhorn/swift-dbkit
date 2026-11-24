/// The untyped parts of a `SELECT`, shared by model queries and projections.
public struct SelectStatement: Sendable {
    var table: String
    /// Projected expressions; `nil` selects `"table".*`.
    var items: [SelectItem]?
    /// Expressions selected after `"table".*`, e.g. the parent key of a many-to-many load.
    var extraItems: [SelectItem] = []
    var distinct = false
    var joins: [JoinClause] = []
    var filters: [SQLNode] = []
    var groupBy: [SQLNode] = []
    var having: [SQLNode] = []
    var orderBy: [OrderBy] = []
    var limit: Int?
    var offset: Int?

    init(table: String) {
        self.table = table
    }
}

struct SelectItem: Sendable {
    let node: SQLNode
    let alias: String?
}

enum JoinKind: String, Sendable {
    case inner = "JOIN"
    case left = "LEFT JOIN"
}

enum JoinClause: Sendable {
    case relation(Relation, JoinKind)
    case table(String, on: SQLNode, JoinKind)
}

/// A relation joined for eager loading, with the joined relations of its children.
struct JoinedLoad: Sendable {
    let step: Int
    let relation: Relation
    let nested: [JoinedLoad]
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
        case .null:
            return "NULL"
        case .raw(let sql):
            return sql
        case .sequence(let nodes):
            return nodes.map { render($0) }.joined()
        }
    }

    func renderSelect(_ statement: SelectStatement, eagerJoins: [JoinedLoad]) -> String {
        let scope = JoinScope(base: statement.table)
        for join in statement.joins {
            switch join {
            case .relation(let relation, let kind): _ = scope.alias(for: relation.path, kind: kind, renderer: self)
            case .table(let table, let condition, let kind): scope.addTableJoin(table, on: condition, kind: kind, renderer: self)
            }
        }

        var columns: [String]
        if let items = statement.items {
            columns = items.map { renderItem($0) }
        } else {
            columns = ["\(quoted(statement.table)).*"] + statement.extraItems.map { renderItem($0) }
            columns += eagerColumns(eagerJoins, path: [], prefix: "", in: scope)
        }

        var clauses: [String] = []
        if !statement.filters.isEmpty {
            clauses.append("WHERE " + statement.filters.map { render($0) }.joined(separator: " AND "))
        }
        if !statement.groupBy.isEmpty {
            clauses.append("GROUP BY " + statement.groupBy.map { render($0) }.joined(separator: ", "))
        }
        if !statement.having.isEmpty {
            clauses.append("HAVING " + statement.having.map { render($0) }.joined(separator: " AND "))
        }
        if !statement.orderBy.isEmpty {
            let orders = statement.orderBy.map { render($0.node) + ($0.descending ? " DESC" : " ASC") }
            clauses.append("ORDER BY " + orders.joined(separator: ", "))
        }
        if let limit = statement.limit { clauses.append("LIMIT \(limit)") }
        if let offset = statement.offset { clauses.append("OFFSET \(offset)") }

        let head = "SELECT \(statement.distinct ? "DISTINCT " : "")\(columns.joined(separator: ", ")) FROM \(quoted(statement.table))"
        return ([head] + scope.joins + clauses).joined(separator: " ")
    }

    private func renderItem(_ item: SelectItem) -> String {
        let sql = render(item.node)
        return item.alias.map { "\(sql) AS \(quoted($0))" } ?? sql
    }

    /// Selects each eager-joined model's columns as `"<relation path>.<column>"`.
    private func eagerColumns(_ joins: [JoinedLoad], path: [Relation], prefix: String, in scope: JoinScope) -> [String] {
        joins.flatMap { join -> [String] in
            var relation = join.relation
            relation.parents = path
            let alias = scope.alias(for: relation.path, kind: .left, renderer: self)
            let childPrefix = prefix + relation.name + "."
            let columns = relation.target.schema.columns.map { "\(quoted(alias)).\(quoted($0)) AS \(quoted(childPrefix + $0))" }
            return columns + eagerColumns(join.nested, path: relation.path, prefix: childPrefix, in: scope)
        }
    }
}

/// The joins of one `SELECT`. Relation paths share one join per path; a join is aliased by its table name
/// unless that name is taken, so plain columns of a joined model (`TodoModel.title`) resolve to the join.
final class JoinScope {
    private let base: String
    private var aliases: [[String]: String] = [:]
    private var usedNames: Set<String>
    private(set) var joins: [String] = []

    init(base: String) {
        self.base = base
        self.usedNames = [base]
    }

    func alias(for path: [Relation], kind: JoinKind, renderer: SQLRenderer) -> String {
        let names = path.map(\.name)
        if let alias = aliases[names] { return alias }
        let relation = path[path.count - 1]
        let parent = path.count == 1 ? base : alias(for: Array(path.dropLast()), kind: kind, renderer: renderer)
        let alias = uniqueName(relation.target.schema.table, fallback: base + "." + names.joined(separator: "."))
        aliases[names] = alias

        let target = relation.target.schema.table
        switch relation.kind {
        case .belongsTo, .hasMany:
            joins.append(
                "\(kind.rawValue) \(tableReference(target, alias)) ON \(quoted(alias)).\(quoted(relation.targetColumn)) = "
                    + "\(quoted(parent)).\(quoted(relation.sourceColumn))"
            )
        case .manyToMany(let through):
            let throughAlias = uniqueName(through.table, fallback: alias + ".through")
            joins.append(
                "\(kind.rawValue) \(tableReference(through.table, throughAlias)) ON \(quoted(throughAlias)).\(quoted(through.sourceColumn)) = "
                    + "\(quoted(parent)).\(quoted(relation.sourceColumn))"
            )
            joins.append(
                "\(kind.rawValue) \(tableReference(target, alias)) ON \(quoted(alias)).\(quoted(relation.targetColumn)) = "
                    + "\(quoted(throughAlias)).\(quoted(through.targetColumn))"
            )
        }
        return alias
    }

    func addTableJoin(_ table: String, on condition: SQLNode, kind: JoinKind, renderer: SQLRenderer) {
        usedNames.insert(table)
        joins.append("\(kind.rawValue) \(quoted(table)) ON \(renderer.render(condition))")
    }

    private func uniqueName(_ name: String, fallback: String) -> String {
        let alias = usedNames.contains(name) ? fallback : name
        usedNames.insert(alias)
        return alias
    }

    private func tableReference(_ table: String, _ alias: String) -> String {
        table == alias ? quoted(table) : "\(quoted(table)) AS \(quoted(alias))"
    }
}

/// Quotes an SQL identifier.
func quoted(_ identifier: String) -> String {
    "\"" + identifier.replacing("\"", with: "\"\"") + "\""
}
