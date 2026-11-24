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

/// Renders statements to SQL, numbering bind placeholders across subqueries in SQL text order.
final class SQLRenderer {
    private(set) var binds: [Bind] = []
    /// Each rendered column's qualifier with the scope that provides it, so a custom join can tell which joins its
    /// condition needs.
    private(set) var references: [(scope: JoinScope, qualifier: String)] = []

    func render(_ node: SQLNode, in scope: JoinScope) -> String {
        switch node {
        case .column(let column):
            let (qualifier, provider) = scope.resolve(column)
            if let provider { references.append((provider, qualifier)) }
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
            return "(\(renderSelect(statement, eagerJoins: [], enclosing: scope)))"
        }
    }

    /// Renders a `SELECT`; `enclosing` is the scope of the statement a subquery is part of.
    func renderSelect(_ statement: SelectStatement, eagerJoins: [JoinedLoad], enclosing: JoinScope? = nil) -> String {
        let scope = JoinScope(planning: statement, eagerJoins: eagerJoins, enclosing: enclosing)
        let base = scope.base

        var columns: [String]
        if let items = statement.items {
            columns = items.map { renderItem($0, in: scope) }
        } else {
            columns = ["\(quoted(base)).*"] + statement.extraItems.map { renderItem($0, in: scope) }
            columns += eagerColumns(eagerJoins, path: [], prefix: "", in: scope)
        }

        let joins = scope.orderedJoins().map { renderJoin($0, in: scope) }

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
            var clause = joins.isEmpty ? "FOR UPDATE" : "FOR UPDATE OF \(quoted(base))"
            switch lock {
            case .wait: break
            case .skipLocked: clause += " SKIP LOCKED"
            case .noWait: clause += " NOWAIT"
            }
            clauses.append(clause)
        }

        let from = statement.alias.map { "\(quoted(statement.table)) AS \(quoted($0))" } ?? quoted(statement.table)
        let head = "SELECT \(statement.distinct ? "DISTINCT " : "")\(columns.joined(separator: ", ")) FROM \(from)"
        return ([head] + joins + clauses).joined(separator: " ")
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
            let alias = scope.relationJoin(relation.path.map(\.name)).alias
            let childPrefix = prefix + relation.name + "."
            let columns = relation.target.schema.columns.map { "\(quoted(alias)).\(quoted($0)) AS \(quoted(childPrefix + $0))" }
            return columns + eagerColumns(join.nested, path: relation.path, prefix: childPrefix, in: scope)
        }
    }

    private func renderJoin(_ join: PlannedJoin, in scope: JoinScope) -> String {
        switch join {
        case .table(let table, let condition, let kind):
            return "\(kind.rawValue) \(quoted(table)) ON \(render(condition, in: scope))"
        case .relation(let names):
            let join = scope.relationJoin(names)
            let relation = join.relation
            let kind = join.kind.rawValue
            let target = tableReference(relation.target.schema.table, join.alias)
            switch relation.kind {
            case .belongsTo, .hasMany:
                return "\(kind) \(target) ON \(quoted(join.alias)).\(quoted(relation.targetColumn)) = "
                    + "\(quoted(join.parent)).\(quoted(relation.sourceColumn))"
            case .manyToMany(let through):
                let throughAlias = join.throughAlias!
                return
                    "\(kind) \(tableReference(through.table, throughAlias)) ON \(quoted(throughAlias)).\(quoted(through.sourceColumn)) = "
                    + "\(quoted(join.parent)).\(quoted(relation.sourceColumn)) "
                    + "\(kind) \(target) ON \(quoted(join.alias)).\(quoted(relation.targetColumn)) = "
                    + "\(quoted(throughAlias)).\(quoted(through.targetColumn))"
            }
        }
    }

    private func tableReference(_ table: String, _ alias: String) -> String {
        table == alias ? quoted(table) : "\(quoted(table)) AS \(quoted(alias))"
    }
}

/// A join of one statement, as planned by ``JoinScope``.
enum PlannedJoin {
    /// The relation join of a path, identified by its relation names.
    case relation([String])
    /// A custom `join(_:on:)`.
    case table(String, on: SQLNode, JoinKind)
}

/// The join of a relation path, shared by every use of the path in one statement.
struct RelationJoin {
    /// The path's last relation.
    let relation: Relation
    let alias: String
    /// The qualifier of the row the relation starts from: the base or the parent path's join.
    let parent: String
    /// The join table's name, for a many-to-many relation.
    let throughAlias: String?
    var kind: JoinKind
}

/// The joins of one statement and the names its columns resolve to. Every join is planned before any SQL is written,
/// so a clause can use a join that a later clause adds, and a subquery sees every name of its enclosing statements.
///
/// A relation join is named by its table, unless this statement or an enclosing one already uses that name: then by
/// the base and the relation names (`"path_records.owner"`), so it never hides another table.
final class JoinScope {
    /// The name the statement's own table goes by.
    let base: String
    /// The scope of the statement this one is a subquery of; a mutation's target table counts as one.
    let enclosing: JoinScope?
    /// Relation and custom joins in the order they were first needed: explicit joins in builder order, each custom
    /// join after the paths of its condition, then the paths of columns, filters, groups, `HAVING` and `ORDER BY`.
    private var joins: [PlannedJoin] = []
    private var relationJoins: [[String]: RelationJoin] = [:]
    private var customTables: Set<String> = []
    /// Every name this statement's `FROM` and joins use.
    private var names: Set<String>

    /// A scope without joins, as for a mutation's target table.
    init(base: String, enclosing: JoinScope? = nil) {
        self.base = base
        self.enclosing = enclosing
        self.names = [base]
    }

    convenience init(planning statement: SelectStatement, eagerJoins: [JoinedLoad], enclosing: JoinScope?) {
        self.init(base: statement.alias ?? statement.table, enclosing: enclosing)
        for case .table(let table, _, _) in statement.joins {
            customTables.insert(table)
            names.insert(table)
        }
        for join in statement.joins {
            switch join {
            case .relation(let relation, let kind):
                addJoin(for: relation.path, explicitKind: kind)
            case .table(let table, let condition, let kind):
                addJoins(for: condition)
                joins.append(.table(table, on: condition, kind))
            }
        }
        if let items = statement.items {
            items.forEach { addJoins(for: $0.node) }
        } else {
            statement.extraItems.forEach { addJoins(for: $0.node) }
            addEagerJoins(eagerJoins, parents: [])
        }
        for node in statement.filters + statement.groupBy + statement.having + statement.orderBy.map(\.node) {
            addJoins(for: node)
        }
    }

    /// The planned join of a path, by its relation names.
    func relationJoin(_ names: [String]) -> RelationJoin {
        relationJoins[names]!
    }

    /// A column's qualifier and the scope that provides it, `nil` for a table no scope provides.
    ///
    /// A path column refers to this statement's join of its path. A plain column of a table refers to the first of:
    /// this statement's own table or custom join of it; the nearest enclosing statement that binds the table (see
    /// `binding(of:)`); this statement's only relation join to it; the table itself.
    func resolve(_ column: ColumnReference) -> (qualifier: String, provider: JoinScope?) {
        if !column.path.isEmpty {
            guard let join = relationJoins[column.path.map(\.name)] else {
                preconditionFailure("relation paths are only supported in SELECT queries")
            }
            return (join.alias, self)
        }
        let table = column.table
        if table == base || customTables.contains(table) { return (table, self) }
        var scope = enclosing
        while let outer = scope {
            if let qualifier = outer.binding(of: table) { return (qualifier, outer) }
            scope = outer.enclosing
        }
        if let alias = onlyRelationAlias(to: table) { return (alias, self) }
        return (table, nil)
    }

    /// The joins in SQL order. Custom joins keep builder order; a relation join moves, together with its parents,
    /// just before the first custom join whose condition uses it or a join it is the parent of, because a condition
    /// only sees the tables joined before it.
    func orderedJoins() -> [PlannedJoin] {
        var ordered: [PlannedJoin] = []
        var placed: Set<[String]> = []
        for join in joins {
            switch join {
            case .relation(let path):
                if placed.insert(path).inserted { ordered.append(join) }
            case .table(_, let condition, _):
                let needed = relationPaths(usedBy: condition)
                for case .relation(let path) in joins where needed.contains(path) && !placed.contains(path) {
                    placed.insert(path)
                    ordered.append(.relation(path))
                }
                ordered.append(join)
            }
        }
        return ordered
    }

    /// The name a subquery's plain column of `table` takes from this statement: its own table or custom join of it,
    /// else its only relation join to it. Two relation joins to the table bind nothing, leaving it to scopes further out.
    private func binding(of table: String) -> String? {
        table == base || customTables.contains(table) ? table : onlyRelationAlias(to: table)
    }

    private func onlyRelationAlias(to table: String) -> String? {
        let matches = relationJoins.values.filter { $0.relation.target.schema.table == table }
        return matches.count == 1 ? matches[0].alias : nil
    }

    /// The paths of this statement's relation joins a condition uses, directly or as a correlation from a subquery at
    /// any depth, with their parents.
    private func relationPaths(usedBy condition: SQLNode) -> Set<[String]> {
        let probe = SQLRenderer()
        _ = probe.render(condition, in: self)
        let aliases = Set(probe.references.filter { $0.scope === self }.map(\.qualifier))
        var paths: Set<[String]> = []
        for (path, join) in relationJoins where aliases.contains(join.alias) {
            for length in 1...path.count { paths.insert(Array(path.prefix(length))) }
        }
        return paths
    }

    /// Plans the joins of the relation paths in `node`. A subquery plans its own paths when it is rendered.
    private func addJoins(for node: SQLNode) {
        switch node {
        case .column(let column) where !column.path.isEmpty: addJoin(for: column.path)
        case .sequence(let nodes): nodes.forEach(addJoins)
        case .column, .bind, .null, .raw, .subquery: break
        }
    }

    private func addEagerJoins(_ loads: [JoinedLoad], parents: [Relation]) {
        for load in loads {
            var relation = load.relation
            relation.parents = parents
            addJoin(for: relation.path)
            addEagerJoins(load.nested, parents: relation.path)
        }
    }

    /// Plans the join of `path` after its parents', or sets the kind of an already planned one to `explicitKind`.
    private func addJoin(for path: [Relation], explicitKind: JoinKind? = nil) {
        let names = path.map(\.name)
        if relationJoins[names] != nil {
            if let explicitKind { relationJoins[names]!.kind = explicitKind }
            return
        }
        let parent: String
        if path.count == 1 {
            parent = base
        } else {
            addJoin(for: Array(path.dropLast()))
            parent = relationJoins[Array(names.dropLast())]!.alias
        }
        let relation = path[path.count - 1]
        let alias = unusedName(relation.target.schema.table, fallback: base + "." + names.joined(separator: "."))
        var throughAlias: String?
        if case .manyToMany(let through) = relation.kind { throughAlias = unusedName(through.table, fallback: alias + ".through") }
        relationJoins[names] = RelationJoin(
            relation: relation, alias: alias, parent: parent, throughAlias: throughAlias, kind: explicitKind ?? .left)
        joins.append(.relation(names))
    }

    private func unusedName(_ name: String, fallback: String) -> String {
        let alias = isUsed(name) ? fallback : name
        names.insert(alias)
        return alias
    }

    private func isUsed(_ name: String) -> Bool {
        names.contains(name) || enclosing?.isUsed(name) == true
    }
}

/// Quotes an SQL identifier.
func quoted(_ identifier: String) -> String {
    "\"" + identifier.replacing("\"", with: "\"\"") + "\""
}
