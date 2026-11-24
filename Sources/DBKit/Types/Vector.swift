import Foundation
import NIOCore
import PostgresNIO

/// A pgvector `vector` with a fixed number of dimensions, e.g. `Vector<1536>`.
///
/// Requires the `vector` extension: `CREATE EXTENSION IF NOT EXISTS vector`.
public struct Vector<let dimensions: Int>: Sendable, Hashable, CustomStringConvertible {
    public let values: [Float]

    /// Throws ``DBKitError/invalidVector(_:)`` when the count doesn't match `dimensions` or a value isn't finite.
    public init(_ values: [Float]) throws {
        try validateVector(values, dimensions: dimensions)
        self.values = values
    }

    /// pgvector's text format, e.g. `[1,2,3]`.
    public var description: String { vectorText(values) }
}

/// A pgvector `halfvec`: half-precision storage, half the size of ``Vector``. Values are kept as `Float` in Swift,
/// rounded to half precision, so they equal what PostgreSQL stores.
///
/// Requires pgvector 0.7 or later.
public struct HalfVector<let dimensions: Int>: Sendable, Hashable, CustomStringConvertible {
    public let values: [Float]

    /// Throws ``DBKitError/invalidVector(_:)`` when `dimensions` is outside 1 to 16000, the count doesn't match it,
    /// or a value isn't finite in half precision.
    public init(_ values: [Float]) throws {
        guard (1...16_000).contains(dimensions) else {
            throw DBKitError.invalidVector("halfvec dimensions must be between 1 and 16000, got \(dimensions)")
        }
        try validateVector(values, dimensions: dimensions)
        guard values.allSatisfy({ abs($0) <= 65504 }) else {
            throw DBKitError.invalidVector("halfvec values must be within ±65504")
        }
        self.values = values.map { floatFromHalfBits(halfBits($0)) }
    }

    public var description: String { vectorText(values) }
}

/// Vector types usable with the pgvector distance functions.
public protocol PGVectorType: SQLValue {}

extension Vector: PGVectorType {
    public static var sqlTypeName: String { "vector" }
    public static var needsPlaceholderCast: Bool { true }
    // pgvector's OID differs per database; the placeholder cast tells PostgreSQL the type.
    public static var psqlType: PostgresDataType { PostgresDataType(0) }
    public static var psqlFormat: PostgresFormat { .binary }

    // Binary layout (pgvector `vector_send`): int16 dimensions, int16 unused, float4 values.
    public func encode<JSONEncoder: PostgresJSONEncoder>(into byteBuffer: inout ByteBuffer, context: PostgresEncodingContext<JSONEncoder>) {
        byteBuffer.writeInteger(Int16(values.count))
        byteBuffer.writeInteger(Int16(0))
        for value in values { byteBuffer.writeInteger(value.bitPattern) }
    }

    public init<JSONDecoder: PostgresJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: PostgresDataType,
        format: PostgresFormat,
        context: PostgresDecodingContext<JSONDecoder>
    ) throws {
        let values: [Float]
        switch format {
        case .binary:
            guard let count = buffer.readInteger(as: Int16.self), buffer.readInteger(as: Int16.self) != nil,
                buffer.readableBytes == Int(count) * 4
            else { throw PostgresDecodingError.Code.failure }
            values = (0..<Int(count)).map { _ in Float(bitPattern: buffer.readInteger(as: UInt32.self)!) }
        case .text:
            values = try parseVectorText(buffer.readString(length: buffer.readableBytes) ?? "")
        }
        try self.init(values)
    }
}

extension HalfVector: PGVectorType {
    public static var sqlTypeName: String { "halfvec" }
    public static var needsPlaceholderCast: Bool { true }
    public static var psqlType: PostgresDataType { PostgresDataType(0) }
    public static var psqlFormat: PostgresFormat { .binary }

    // Binary layout (pgvector `halfvec_send`): int16 dimensions, int16 unused, IEEE 754 half values.
    public func encode<JSONEncoder: PostgresJSONEncoder>(into byteBuffer: inout ByteBuffer, context: PostgresEncodingContext<JSONEncoder>) {
        byteBuffer.writeInteger(Int16(values.count))
        byteBuffer.writeInteger(Int16(0))
        for value in values { byteBuffer.writeInteger(halfBits(value)) }
    }

    public init<JSONDecoder: PostgresJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: PostgresDataType,
        format: PostgresFormat,
        context: PostgresDecodingContext<JSONDecoder>
    ) throws {
        let values: [Float]
        switch format {
        case .binary:
            guard let count = buffer.readInteger(as: Int16.self), buffer.readInteger(as: Int16.self) != nil,
                buffer.readableBytes == Int(count) * 2
            else { throw PostgresDecodingError.Code.failure }
            values = (0..<Int(count)).map { _ in floatFromHalfBits(buffer.readInteger(as: UInt16.self)!) }
        case .text:
            values = try parseVectorText(buffer.readString(length: buffer.readableBytes) ?? "")
        }
        try self.init(values)
    }
}

private func validateVector(_ values: [Float], dimensions: Int) throws {
    guard values.count == dimensions else {
        throw DBKitError.invalidVector("expected \(dimensions) dimensions, got \(values.count)")
    }
    guard values.allSatisfy(\.isFinite) else { throw DBKitError.invalidVector("vector values must be finite") }
}

private func vectorText(_ values: [Float]) -> String {
    "[" + values.map { "\($0)" }.joined(separator: ",") + "]"
}

/// Parses pgvector's text format, `[1,2,3]`.
private func parseVectorText(_ text: String) throws -> [Float] {
    let text = text.trimmingCharacters(in: .whitespaces)
    guard text.hasPrefix("["), text.hasSuffix("]") else { throw invalidVectorText }
    let body = text.dropFirst().dropLast()
    guard !body.allSatisfy(\.isWhitespace) else { return [] }
    return try body.split(separator: ",", omittingEmptySubsequences: false).map {
        guard let value = Float($0.trimmingCharacters(in: .whitespaces)) else { throw invalidVectorText }
        return value
    }
}

let invalidVectorText = DBKitError.invalidVector("invalid vector text")

/// Converts to IEEE 754 binary16 with round-to-nearest-even. Values are pre-validated to be finite and in range.
func halfBits(_ value: Float) -> UInt16 {
    let bits = value.bitPattern
    let sign = UInt16((bits >> 16) & 0x8000)
    let exponent = Int((bits >> 23) & 0xFF) - 127 + 15
    var mantissa = bits & 0x7F_FFFF
    if exponent <= 0 {
        // Subnormal half (or zero): shift the implicit leading bit into the mantissa.
        guard exponent >= -10 else { return sign }
        mantissa |= 0x80_0000
        let shift = UInt32(14 - exponent)
        var half = mantissa >> shift
        let remainder = mantissa & ((1 << shift) - 1)
        let halfway = UInt32(1) << (shift - 1)
        if remainder > halfway || (remainder == halfway && half & 1 == 1) { half += 1 }
        return sign | UInt16(half)
    }
    var half = UInt32(exponent) << 10 | mantissa >> 13
    let remainder = mantissa & 0x1FFF
    if remainder > 0x1000 || (remainder == 0x1000 && half & 1 == 1) { half += 1 }
    return sign | UInt16(min(half, 0x7BFF))
}

func floatFromHalfBits(_ half: UInt16) -> Float {
    let sign: Float = half & 0x8000 == 0 ? 1 : -1
    let exponent = Int(half >> 10) & 0x1F
    let mantissa = Float(half & 0x3FF)
    switch exponent {
    case 0: return sign * mantissa * Float(sign: .plus, exponent: -24, significand: 1)
    case 0x1F: return mantissa == 0 ? sign * .infinity : .nan
    default: return sign * (1 + mantissa / 1024) * Float(sign: .plus, exponent: exponent - 15, significand: 1)
    }
}
