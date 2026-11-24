/// The untyped SQL syntax tree that typed expressions compile to.
public indirect enum SQLNode: Sendable {
    case column(ColumnReference)
    case bind(Bind)
    case null
    /// SQL text emitted verbatim. Only ever built from DBKit's fixed keywords and identifiers.
    case raw(String)
    case sequence([SQLNode])

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

/// A model column.
public struct ColumnReference: Sendable {
    let table: String
    let name: String
}

/// A bind parameter value.
public struct Bind: Sendable, CustomStringConvertible {
    public let value: any SQLValue

    public init(_ value: some SQLValue) {
        self.value = value
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
