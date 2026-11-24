import DBKit

/// The bytes `value` sends to PostgreSQL in its binary format.
func wireBytes(_ value: some PostgresEncodable) throws -> [UInt8] {
    var buffer = ByteBuffer()
    try value.encode(into: &buffer, context: .default)
    return Array(buffer.readableBytesView)
}

/// Decodes a value as PostgreSQL sends it in the binary format.
func decodeBinary<Value: PostgresDecodable>(_ bytes: [UInt8], as type: Value.Type) throws -> Value {
    var buffer = ByteBuffer(bytes: bytes)
    return try Value(from: &buffer, type: .text, format: .binary, context: .default)
}

/// Decodes a value as PostgreSQL sends it in the text format, such as `[1,2,3]` for a `vector`.
func decodeText<Value: PostgresDecodable>(_ text: String, as type: Value.Type) throws -> Value {
    var buffer = ByteBuffer(string: text)
    return try Value(from: &buffer, type: .text, format: .text, context: .default)
}
