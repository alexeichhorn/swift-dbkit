/// The untyped SQL syntax tree that typed expressions compile to.
public indirect enum SQLNode: Sendable {
    case column(ColumnReference)
    case bind(Bind)
    case null
    /// SQL text emitted verbatim. Only ever built from DBKit's fixed keywords and identifiers.
    case raw(String)
    case sequence([SQLNode])

    static func infix(_ lhs: SQLNode, _ op: String, _ rhs: SQLNode, parenthesized: Bool = true) -> SQLNode {
        parenthesized ? .sequence([.raw("("), lhs, .raw(" \(op) "), rhs, .raw(")")]) : .sequence([lhs, .raw(" \(op) "), rhs])
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
