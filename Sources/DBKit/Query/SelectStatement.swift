/// The untyped parts of a `SELECT`, shared by model queries, projections and subqueries.
public struct SelectStatement: Sendable {
    var table: String
    /// The name the table goes by in this `SELECT` (`FROM "table" AS "alias"`), set by ``ModelAlias/query()``.
    var alias: String?
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
    var lock: RowLock?

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

/// Waiting behavior of `SELECT … FOR UPDATE`.
public enum RowLock: Sendable {
    /// Wait for conflicting locks to be released.
    case wait
    /// Skip rows that other transactions have locked, e.g. for job queues.
    case skipLocked
    /// Fail immediately when a row is locked.
    case noWait
}

/// A relation joined for eager loading, with the joined relations of its children.
struct JoinedLoad: Sendable {
    let step: Int
    let relation: Relation
    let nested: [JoinedLoad]
}

/// Renders statements to SQL, numbering bind placeholders across subqueries.
final class SQLRenderer {
    private(set) var binds: [Bind] = []

    func render(_ node: SQLNode, in scope: JoinScope) -> String {
        switch node {
        case .column(let column):
            let qualifier = column.path.isEmpty ? column.table : scope.alias(for: column.path, kind: .left, renderer: self)
            return "\(quoted(qualifier)).\(quoted(column.name))"
        case .bind(let bind):
            binds.append(bind)
            return "$\(binds.count)"
        case .null:
            return "NULL"
        case .raw(let sql):
            return sql
        case .sequence(let nodes):
            return nodes.map { render($0, in: scope) }.joined()
        case .subquery(let statement):
            return "(\(renderSelect(statement, eagerJoins: [])))"
        }
    }

    func renderSelect(_ statement: SelectStatement, eagerJoins: [JoinedLoad]) -> String {
        let base = statement.alias ?? statement.table
        let scope = JoinScope(base: base)
        for join in statement.joins {
            switch join {
            case .relation(let relation, let kind): _ = scope.alias(for: relation.path, kind: kind, renderer: self)
            case .table(let table, let condition, let kind): scope.addTableJoin(table, on: condition, kind: kind, renderer: self)
            }
        }

        var columns: [String]
        if let items = statement.items {
            columns = items.map { renderItem($0, in: scope) }
        } else {
            columns = ["\(quoted(base)).*"] + statement.extraItems.map { renderItem($0, in: scope) }
            columns += eagerColumns(eagerJoins, path: [], prefix: "", in: scope)
        }

        var clauses: [String] = []
        if !statement.filters.isEmpty {
            clauses.append("WHERE " + statement.filters.map { render($0, in: scope) }.joined(separator: " AND "))
        }
        if !statement.groupBy.isEmpty {
            clauses.append("GROUP BY " + statement.groupBy.map { render($0, in: scope) }.joined(separator: ", "))
        }
        if !statement.having.isEmpty {
            clauses.append("HAVING " + statement.having.map { render($0, in: scope) }.joined(separator: " AND "))
        }
        if !statement.orderBy.isEmpty {
            let orders = statement.orderBy.map { render($0.node, in: scope) + ($0.descending ? " DESC" : " ASC") }
            clauses.append("ORDER BY " + orders.joined(separator: ", "))
        }
        if let limit = statement.limit { clauses.append("LIMIT \(limit)") }
        if let offset = statement.offset { clauses.append("OFFSET \(offset)") }
        if let lock = statement.lock {
            // Scope the lock to the base table so outer-joined rows aren't locked (PostgreSQL rejects locking
            // the nullable side of an outer join).
            var clause = scope.joins.isEmpty ? "FOR UPDATE" : "FOR UPDATE OF \(quoted(base))"
            switch lock {
            case .wait: break
            case .skipLocked: clause += " SKIP LOCKED"
            case .noWait: clause += " NOWAIT"
            }
            clauses.append(clause)
        }

        let from = statement.alias.map { "\(quoted(statement.table)) AS \(quoted($0))" } ?? quoted(statement.table)
        let head = "SELECT \(statement.distinct ? "DISTINCT " : "")\(columns.joined(separator: ", ")) FROM \(from)"
        return ([head] + scope.joins + clauses).joined(separator: " ")
    }

    private func renderItem(_ item: SelectItem, in scope: JoinScope) -> String {
        let sql = render(item.node, in: scope)
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
        joins.append("\(kind.rawValue) \(quoted(table)) ON \(renderer.render(condition, in: self))")
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
