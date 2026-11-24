import NIOCore
import PostgresNIO

/// A PostgreSQL `bit(n)` string of fixed length, e.g. `BitVector<256>` for a binary embedding that pgvector compares
/// with `hammingDistance(to:)` and `jaccardDistance(to:)`.
public struct BitVector<let dimensions: Int>: Sendable, Hashable, CustomStringConvertible {
    public let values: [Bool]

    /// Throws ``DBKitError/invalidVector(_:)`` when `dimensions` is outside 1 to 2,147,483,640 or the count doesn't
    /// match it.
    public init(_ values: [Bool]) throws {
        guard (1...2_147_483_640).contains(dimensions) else {
            throw DBKitError.invalidVector("bit dimensions must be between 1 and 2147483640, got \(dimensions)")
        }
        guard values.count == dimensions else {
            throw DBKitError.invalidVector("expected \(dimensions) dimensions, got \(values.count)")
        }
        self.values = values
    }

    /// PostgreSQL's text format, e.g. `010000001`.
    public var description: String { String(values.map { $0 ? "1" : "0" }) }
}

/// Bit string types usable with pgvector's Hamming and Jaccard distances.
public protocol PGBitType: SQLValue {}

extension BitVector: PGBitType {
    /// The cast carries the length, so a value binds to a `bit(n)` column of its own length.
    public static var sqlTypeName: String { "bit(\(dimensions))" }
    public static var needsPlaceholderCast: Bool { true }
    public static var psqlType: PostgresDataType { .bit }
    public static var psqlFormat: PostgresFormat { .binary }

    // Binary layout (PostgreSQL `bit_send`): int32 length, then the bits packed from the most significant, with zeros
    // after the last bit.
    public func encode<JSONEncoder: PostgresJSONEncoder>(into byteBuffer: inout ByteBuffer, context: PostgresEncodingContext<JSONEncoder>) {
        byteBuffer.writeInteger(Int32(values.count))
        for start in stride(from: 0, to: values.count, by: 8) {
            var byte: UInt8 = 0
            for (offset, bit) in values[start..<min(start + 8, values.count)].enumerated() where bit {
                byte |= 0x80 >> offset
            }
            byteBuffer.writeInteger(byte)
        }
    }

    public init<JSONDecoder: PostgresJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: PostgresDataType,
        format: PostgresFormat,
        context: PostgresDecodingContext<JSONDecoder>
    ) throws {
        switch format {
        case .binary:
            guard let length = buffer.readInteger(as: Int32.self) else { throw PostgresDecodingError.Code.failure }
            guard length == dimensions else {
                throw DBKitError.invalidVector("expected \(dimensions) dimensions, got \(length)")
            }
            guard let bytes = buffer.readBytes(length: buffer.readableBytes), bytes.count == (dimensions + 7) / 8,
                dimensions % 8 == 0 || bytes.last! & (0xFF >> (dimensions % 8)) == 0
            else { throw PostgresDecodingError.Code.failure }
            try self.init((0..<dimensions).map { bytes[$0 / 8] & (0x80 >> ($0 % 8)) != 0 })
        case .text:
            let text = buffer.readString(length: buffer.readableBytes) ?? ""
            guard text.allSatisfy({ $0 == "0" || $0 == "1" }) else { throw invalidVectorText }
            try self.init(text.map { $0 == "1" })
        }
    }
}
