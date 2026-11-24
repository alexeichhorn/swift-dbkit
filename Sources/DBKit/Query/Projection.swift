import Foundation
import PostgresNIO

/// A `SELECT` of expressions instead of models, created by `Query.select(…)`. Rows decode as the tuple
/// `(repeat each Value)`, so result types follow the selected expressions.
public struct Projection<each Value: SQLType>: SelectQuery {
    public var statement: SelectStatement

    public func render() -> RenderedSQL {
        let renderer = SQLRenderer()
        let sql = renderer.renderSelect(statement)
        return RenderedSQL(sql: sql, binds: renderer.binds)
    }

    public func all(on executor: some DatabaseExecutor) async throws -> [(repeat each Value)] {
        try await executor.rows(render()) { row in
            var index = 0
            func next<V: SQLType>(_ type: V.Type) throws -> V {
                defer { index += 1 }
                return try V.decode(from: row[index])
            }
            return (repeat try next((each Value).self))
        }
    }

    /// The first row (`LIMIT 1`).
    public func first(on executor: some DatabaseExecutor) async throws -> (repeat each Value)? {
        try await limit(1).all(on: executor).first
    }

    /// Decodes rows into `T`, matching each property to the column alias of the same name or its snake_case form.
    public func all<T: Decodable>(as type: T.Type, on executor: some DatabaseExecutor) async throws -> [T] {
        try await executor.rows(render()) { try T(from: RowDecoder(row: $0)) }
    }

    public func first<T: Decodable>(as type: T.Type, on executor: some DatabaseExecutor) async throws -> T? {
        try await limit(1).all(as: type, on: executor).first
    }
}

/// The select list of a `@Projection` type, built by its generated `columns(…)`. Pass it to `Query.select(_:)`.
public struct ProjectionColumns<Row: Sendable>: Sendable {
    let nodes: [SQLNode]
    let decode: @Sendable (inout ProjectionReader) throws -> Row

    /// For `@Projection`. `decode` reads one value per node, in order.
    public init(_ nodes: [SQLNode], decode: @escaping @Sendable (inout ProjectionReader) throws -> Row) {
        self.nodes = nodes
        self.decode = decode
    }
}

/// Reads the values of one result row in select-list order.
public struct ProjectionReader {
    let row: PostgresRandomAccessRow
    var index = 0

    public mutating func next<Value: SQLType>() throws -> Value {
        defer { index += 1 }
        return try Value.decode(from: row[index])
    }
}

/// A `SELECT` whose rows decode into a `@Projection` type, created by `Query.select(_:)`.
public struct ProjectionQuery<Row: Sendable>: SelectQuery {
    public var statement: SelectStatement
    let decode: @Sendable (inout ProjectionReader) throws -> Row

    public func render() -> RenderedSQL {
        let renderer = SQLRenderer()
        let sql = renderer.renderSelect(statement)
        return RenderedSQL(sql: sql, binds: renderer.binds)
    }

    public func all(on executor: some DatabaseExecutor) async throws -> [Row] {
        try await executor.rows(render()) { row in
            var reader = ProjectionReader(row: row)
            return try decode(&reader)
        }
    }

    /// The first row (`LIMIT 1`).
    public func first(on executor: some DatabaseExecutor) async throws -> Row? {
        try await limit(1).all(on: executor).first
    }
}

/// Decodes a flat `Decodable` struct from named result columns.
private struct RowDecoder: Decoder {
    let row: PostgresRandomAccessRow
    var codingPath: [any CodingKey] { [] }
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(Container(row: row))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self, .init(codingPath: [], debugDescription: "rows decode as keyed structs"))
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw DecodingError.typeMismatch(Any.self, .init(codingPath: [], debugDescription: "rows decode as keyed structs"))
    }

    struct Container<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let row: PostgresRandomAccessRow
        var codingPath: [any CodingKey] { [] }
        var allKeys: [Key] { [] }

        func contains(_ key: Key) -> Bool { column(for: key) != nil }

        func decodeNil(forKey key: Key) throws -> Bool { try cell(for: key).bytes == nil }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            guard let sqlType = T.self as? any SQLType.Type else {
                throw DecodingError.typeMismatch(T.self, .init(codingPath: [key], debugDescription: "\(T.self) is not a SQLType"))
            }
            return try sqlType.decode(from: cell(for: key)) as! T
        }

        func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<
            NestedKey
        > {
            throw DecodingError.typeMismatch(type, .init(codingPath: [key], debugDescription: "nested values aren't supported"))
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
            throw DecodingError.typeMismatch([Any].self, .init(codingPath: [key], debugDescription: "nested values aren't supported"))
        }

        func superDecoder() throws -> any Decoder { RowDecoder(row: row) }
        func superDecoder(forKey key: Key) throws -> any Decoder { RowDecoder(row: row) }

        private func column(for key: Key) -> String? {
            [key.stringValue, snakeCased(key.stringValue)].first(where: row.contains)
        }

        private func cell(for key: Key) throws -> PostgresCell {
            guard let column = column(for: key) else { throw DBKitError.missingColumn(key.stringValue) }
            return row[column]
        }
    }
}

/// `userID` → `user_id`, `HTTPWebhook` → `http_webhook`. Mirrors the column naming of `@Model`.
func snakeCased(_ name: String) -> String {
    let characters = Array(name)
    var result = ""
    for (index, character) in characters.enumerated() {
        if character.isUppercase, index > 0 {
            let previous = characters[index - 1]
            let nextIsLower = index + 1 < characters.count && characters[index + 1].isLowercase
            if previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLower) { result.append("_") }
        }
        result += character.lowercased()
    }
    return result
}
