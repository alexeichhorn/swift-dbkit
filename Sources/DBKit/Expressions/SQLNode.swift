/// The untyped SQL syntax tree that typed expressions compile to.
public indirect enum SQLNode: Sendable {
    case column(ColumnReference)
    case bind(Bind)
    case null
    /// SQL text emitted verbatim. Only ever built from DBKit's fixed keywords and identifiers.
    case raw(String)
    case sequence([SQLNode])
    case subquery(SelectStatement)

    static func function(_ name: String, _ arguments: [SQLNode]) -> SQLNode {
        var parts: [SQLNode] = [.raw("\(name)(")]
        for (index, argument) in arguments.enumerated() {
            if index > 0 { parts.append(.raw(", ")) }
            parts.append(argument)
        }
        parts.append(.raw(")"))
        return .sequence(parts)
    }

    static func infix(_ lhs: SQLNode, _ op: String, _ rhs: SQLNode, parenthesized: Bool = true) -> SQLNode {
        parenthesized ? .sequence([.raw("("), lhs, .raw(" \(op) "), rhs, .raw(")")]) : .sequence([lhs, .raw(" \(op) "), rhs])
    }

    /// `lhs op rhs` for a comparison operator, bare on its own. PostgreSQL's comparisons don't chain: `a = b > c` is a
    /// syntax error and `a = b IS NULL` reads as `(a = b) IS NULL`. So an operand that is a comparison is parenthesized.
    static func comparison(_ lhs: SQLNode, _ op: String, _ rhs: SQLNode) -> SQLNode {
        .sequence([lhs.parenthesizedIfComparison, .raw(" \(op) "), rhs.parenthesizedIfComparison])
    }

    /// `operand IS NULL` or `operand IS NOT NULL`, a comparison like those of `comparison(_:_:_:)`.
    static func nullCheck(_ operand: SQLNode, _ check: String) -> SQLNode {
        .sequence([operand.parenthesizedIfComparison, .raw(" \(check)")])
    }

    /// The operator texts `comparison(_:_:_:)` and `nullCheck(_:_:)` put second in their sequence.
    private static let comparisonOperators: Set<String> = [
        " = ", " <> ", " < ", " <= ", " > ", " >= ", " IS DISTINCT FROM ", " IS NOT DISTINCT FROM ", " IS NULL", " IS NOT NULL",
    ]

    private var parenthesizedIfComparison: SQLNode {
        guard case .sequence(let parts) = self, parts.count > 1, case .raw(let op) = parts[1], Self.comparisonOperators.contains(op)
        else { return self }
        return .sequence([.raw("("), self, .raw(")")])
    }

    static func list(_ nodes: [SQLNode]) -> SQLNode {
        var parts: [SQLNode] = [.raw("(")]
        for (index, node) in nodes.enumerated() {
            if index > 0 { parts.append(.raw(", ")) }
            parts.append(node)
        }
        parts.append(.raw(")"))
        return .sequence(parts)
    }
}

/// A model column, optionally reached through a chain of `BelongsTo` relations (a relation path).
public struct ColumnReference: Sendable {
    /// The qualifier: the model's table, or the alias of a ``ModelAlias``.
    let table: TableName
    let name: String
    /// Relations walked from the query's model to the column's table; empty for direct columns.
    let path: [Relation]
}

/// A table as a statement names it: `"app"."users"` for a table in a schema, `"users"` without one. An alias is a name
/// without a schema.
struct TableName: Hashable, Sendable {
    let schema: String?
    /// The bare name. PostgreSQL tells the tables of a statement apart by it, also across schemas, and `FOR UPDATE OF`
    /// takes only it.
    let name: String

    static func alias(_ name: String) -> TableName { TableName(schema: nil, name: name) }

    /// The quoted name, qualified by its schema.
    var sql: String { (schema.map { quoted($0) + "." } ?? "") + quoted(name) }
}

/// A bind parameter value.
public struct Bind: Sendable, CustomStringConvertible {
    public let value: any SQLValue

    public init(_ value: some SQLValue) {
        self.value = value
    }

    /// The `::type` suffix for placeholders whose type the driver can't name.
    var placeholderCast: String? {
        let type = Swift.type(of: value)
        return type.needsPlaceholderCast ? "::\(type.sqlTypeName)" : nil
    }

    public var description: String { String(describing: value) }
}

/// SQL text with numbered placeholders and their values.
public struct RenderedSQL: Sendable, CustomStringConvertible {
    public let sql: String
    public let binds: [Bind]

    public var description: String {
        binds.isEmpty ? sql : "\(sql) -- binds: \(binds.map(\.description))"
    }
}
