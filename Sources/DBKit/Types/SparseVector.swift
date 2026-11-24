import Foundation
import NIOCore
import PostgresNIO

/// A pgvector `sparsevec` with a fixed number of dimensions, e.g. `SparseVector<30000>`. It stores its nonzero
/// entries only.
///
/// Requires pgvector 0.7 or later.
public struct SparseVector<let dimensions: Int>: Sendable, Hashable, CustomStringConvertible {
    /// The zero-based positions of the nonzero entries, ascending.
    public let indices: [Int]
    /// The nonzero values, in the order of `indices`.
    public let values: [Float]

    /// Takes `(index, value)` pairs in any order, with zero-based indices, and drops the zeros.
    ///
    /// Throws ``DBKitError/invalidVector(_:)`` when `dimensions` is outside 1 to 1,000,000,000, an index is out of
    /// bounds or repeated, a value isn't finite, or more than 16000 values are nonzero. A repeated index throws even
    /// when its values are zero.
    public init(_ entries: [(index: Int, value: Float)]) throws {
        guard (1...1_000_000_000).contains(dimensions) else {
            throw DBKitError.invalidVector("sparsevec dimensions must be between 1 and 1000000000, got \(dimensions)")
        }
        let entries = entries.sorted { $0.index < $1.index }
        for (position, entry) in entries.enumerated() {
            guard (0..<dimensions).contains(entry.index) else {
                throw DBKitError.invalidVector("sparsevec index \(entry.index) is out of bounds for \(dimensions) dimensions")
            }
            if position > 0, entries[position - 1].index == entry.index {
                throw DBKitError.invalidVector("sparsevec repeats index \(entry.index)")
            }
            guard entry.value.isFinite else { throw DBKitError.invalidVector("vector values must be finite") }
        }
        let nonzero = entries.filter { $0.value != 0 }
        guard nonzero.count <= 16_000 else {
            throw DBKitError.invalidVector("sparsevec cannot have more than 16000 nonzero entries, got \(nonzero.count)")
        }
        indices = nonzero.map(\.index)
        values = nonzero.map(\.value)
    }

    /// PostgreSQL's text format, with indices counted from 1, e.g. `{1:0.5,43:0.75}/1000`.
    public var description: String {
        "{" + zip(indices, values).map { "\($0 + 1):\($1)" }.joined(separator: ",") + "}/\(dimensions)"
    }
}

extension SparseVector: PGVectorType {
    public static var sqlTypeName: String { "sparsevec" }
    public static var needsPlaceholderCast: Bool { true }
    public static var psqlType: PostgresDataType { PostgresDataType(0) }
    public static var psqlFormat: PostgresFormat { .binary }

    // Binary layout (pgvector `sparsevec_send`): int32 dimensions, int32 count, int32 unused, int32 zero-based
    // indices, float4 values.
    public func encode<JSONEncoder: PostgresJSONEncoder>(into byteBuffer: inout ByteBuffer, context: PostgresEncodingContext<JSONEncoder>) {
        byteBuffer.writeInteger(Int32(dimensions))
        byteBuffer.writeInteger(Int32(indices.count))
        byteBuffer.writeInteger(Int32(0))
        for index in indices { byteBuffer.writeInteger(Int32(index)) }
        for value in values { byteBuffer.writeInteger(value.bitPattern) }
    }

    public init<JSONDecoder: PostgresJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: PostgresDataType,
        format: PostgresFormat,
        context: PostgresDecodingContext<JSONDecoder>
    ) throws {
        switch format {
        case .binary:
            guard let storedDimensions = buffer.readInteger(as: Int32.self), let count = buffer.readInteger(as: Int32.self),
                buffer.readInteger(as: Int32.self) == 0, (0...16_000).contains(count), buffer.readableBytes == Int(count) * 8
            else { throw PostgresDecodingError.Code.failure }
            try Self.checkDimensions(Int(storedDimensions))
            let indices = (0..<Int(count)).map { _ in Int(buffer.readInteger(as: Int32.self)!) }
            let values = (0..<Int(count)).map { _ in Float(bitPattern: buffer.readInteger(as: UInt32.self)!) }
            try self.init(zip(indices, values).map { (index: $0, value: $1) })
        case .text:
            try self.init(text: buffer.readString(length: buffer.readableBytes) ?? "")
        }
    }

    /// Parses PostgreSQL's text format, with indices counted from 1.
    private init(text: String) throws {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let storedDimensions = Int(parts[1]), parts[0].hasPrefix("{"), parts[0].hasSuffix("}") else {
            throw invalidVectorText
        }
        try Self.checkDimensions(storedDimensions)
        let body = parts[0].dropFirst().dropLast()
        let entries: [(index: Int, value: Float)] =
            try body.isEmpty
            ? []
            : body.split(separator: ",", omittingEmptySubsequences: false).map { entry in
                let pair = entry.split(separator: ":", omittingEmptySubsequences: false)
                guard pair.count == 2, let position = Int(pair[0]), position >= 1, let value = Float(pair[1]) else {
                    throw invalidVectorText
                }
                return (index: position - 1, value: value)
            }
        try self.init(entries)
    }

    private static func checkDimensions(_ stored: Int) throws {
        guard stored == dimensions else { throw DBKitError.invalidVector("expected \(dimensions) dimensions, got \(stored)") }
    }
}
