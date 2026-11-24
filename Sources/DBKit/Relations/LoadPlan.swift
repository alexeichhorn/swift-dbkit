import NIOCore
import PostgresNIO

/// How rows of `Row` are assembled from query results: the base row plus every eager-loaded relation.
///
/// Built by `Query.with` and the generated relation types; you don't create plans directly.
public struct LoadPlan<Row: Model>: Sendable {
    let joins: [JoinedLoad]
    let stepCount: Int
    let build: @Sendable ([RawNode], any DatabaseExecutor) async throws -> [Row]

    /// Adds a relation load. Used by generated code.
    public func adding<L: RelationLoad>(_ load: L, _ strategy: LoadStrategy) -> LoadPlan<L.Output> where L.Source == Row {
        let step = stepCount
        let previous = build
        var joins = self.joins
        if strategy == .joined {
            joins.append(JoinedLoad(step: step, relation: load.relation, nested: load.plan.joins))
        }
        return LoadPlan<L.Output>(joins: joins, stepCount: step + 1) { nodes, executor in
            let sources = try await previous(nodes, executor)
            switch strategy {
            case .selectIn:
                return try await selectIn(load, for: sources, on: executor)
            case .joined:
                // Build all children in one pass so their own select-in loads are batched, then split per source.
                let childNodes = nodes.map { $0.joined[step] ?? [] }
                let children = try await load.plan.build(childNodes.flatMap { $0 }, executor)
                var offset = 0
                return zip(sources, childNodes).map { source, nodes in
                    defer { offset += nodes.count }
                    return load.attach(Array(children[offset..<offset + nodes.count]), to: source)
                }
            }
        }
    }
}

extension LoadPlan where Row == Row.Base {
    /// The plan for rows without loaded relations.
    public static var base: LoadPlan<Row> {
        LoadPlan(joins: [], stepCount: 0) { nodes, _ in nodes.map { $0.base as! Row } }
    }
}

/// A decoded row before relations are attached, with the rows of its joined relations by load step.
struct RawNode: Sendable {
    let base: any Model
    /// The key matching a source row, for children fetched by a select-in load.
    var parentKey: KeyValue?
    var joined: [Int: [RawNode]] = [:]

    /// Decodes the columns of `row` that start with `prefix` as `model`.
    private init(row: PostgresRandomAccessRow, model: any Model.Type, prefix: String, parent: Relation?) throws {
        let reader = RowReader(row: row, prefix: prefix)
        base = try model.decodeBase(from: reader)
        parentKey = try parent?.targetKey(base, reader)
    }

    /// Runs the query and decodes its rows of `model`. Without joins each row is decoded as it arrives. Joined rows
    /// are grouped first, so all of them are held until the last one has arrived.
    static func load(
        _ rendered: RenderedSQL,
        model: any Model.Type,
        joins: [JoinedLoad],
        parent: Relation? = nil,
        on executor: some DatabaseExecutor
    ) async throws -> [RawNode] {
        guard joins.isEmpty else {
            return try group(try await executor.rows(rendered) { $0 }, model: model, prefix: "", joins: joins, parent: parent)
        }
        return try await executor.rows(rendered) { try RawNode(row: $0, model: model, prefix: "", parent: parent) }
    }

    /// Decodes joined rows of `model` whose columns start with `prefix`, grouped by primary key so each model appears
    /// once with its joined children; rows whose key is NULL (no joined match) are skipped.
    private static func group(
        _ rows: [PostgresRandomAccessRow],
        model: any Model.Type,
        prefix: String,
        joins: [JoinedLoad],
        parent: Relation? = nil
    ) throws -> [RawNode] {
        var order: [[ByteBuffer?]] = []
        var groups: [[ByteBuffer?]: [PostgresRandomAccessRow]] = [:]
        for row in rows {
            var key = try model.schema.primaryKey.map { column in
                let name = prefix + column
                guard row.contains(name) else { throw DBKitError.missingColumn(name) }
                return row[name].bytes
            }
            guard key.contains(where: { $0 != nil }) else { continue }
            if parent != nil, row.contains(Relation.parentKeyColumn) { key.append(row[Relation.parentKeyColumn].bytes) }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        return try order.map { key in
            let rows = groups[key]!
            var node = try RawNode(row: rows[0], model: model, prefix: prefix, parent: parent)
            for join in joins {
                node.joined[join.step] = try group(
                    rows, model: join.relation.target, prefix: prefix + join.relation.name + ".", joins: join.nested)
            }
            return node
        }
    }
}

/// Loads a relation for `sources` with one `WHERE key = ANY($1)` query (plus the children's own loads).
func selectIn<L: RelationLoad>(_ load: L, for sources: [L.Source], on executor: some DatabaseExecutor) async throws -> [L.Output] {
    let relation = load.relation
    let keys = sources.map { relation.sourceKey($0) }
    var seen: Set<KeyValue> = []
    let uniqueKeys = keys.compactMap { $0 }.filter { seen.insert($0).inserted }
    guard !uniqueKeys.isEmpty else { return sources.map { load.attach([], to: $0) } }

    let target = L.Target.schema
    var statement = SelectStatement(table: target.tableName)
    let keysBind = SQLNode.bind(relation.keyArray(uniqueKeys))
    switch relation.kind {
    case .belongsTo, .hasMany:
        let keyColumn = SQLNode.column(ColumnReference(table: target.tableName, name: relation.targetColumn, path: []))
        statement.filters = [.sequence([keyColumn, .raw(" = ANY("), keysBind, .raw(")")])]
    case .manyToMany(let through):
        let throughSource = SQLNode.column(ColumnReference(table: through.table, name: through.sourceColumn, path: []))
        let throughTarget = SQLNode.column(ColumnReference(table: through.table, name: through.targetColumn, path: []))
        let targetKey = SQLNode.column(ColumnReference(table: target.tableName, name: relation.targetColumn, path: []))
        statement.extraItems = [SelectItem(node: throughSource, alias: Relation.parentKeyColumn)]
        statement.joins = [.table(through.table, on: .infix(throughTarget, "=", targetKey, parenthesized: false), .inner)]
        statement.filters = [.sequence([throughSource, .raw(" = ANY("), keysBind, .raw(")")])]
    }
    statement.orderBy = target.primaryKey.map {
        OrderBy(node: .column(ColumnReference(table: target.tableName, name: $0, path: [])), descending: false)
    }

    let renderer = SQLRenderer()
    let sql = renderer.renderSelect(statement, eagerJoins: load.plan.joins)
    let nodes = try await RawNode.load(
        RenderedSQL(sql: sql, binds: renderer.binds), model: L.Target.self, joins: load.plan.joins, parent: relation, on: executor)
    let children = try await load.plan.build(nodes, executor)

    var childrenByKey: [KeyValue: [L.Child]] = [:]
    for (node, child) in zip(nodes, children) {
        if let key = node.parentKey { childrenByKey[key, default: []].append(child) }
    }
    return zip(sources, keys).map { source, key in load.attach(key.flatMap { childrenByKey[$0] } ?? [], to: source) }
}
