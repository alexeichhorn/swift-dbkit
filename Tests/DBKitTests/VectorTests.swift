import DBKit
import Testing

@Suite struct VectorTests {
    @Test func binaryFormatsRoundTripAndValidate() throws {
        let vector = try Vector<3>([1, -0.5, 0.25])
        var buffer = ByteBuffer()
        vector.encode(into: &buffer, context: .default)
        // int16 dimensions, int16 unused, then big-endian float4 values.
        #expect(Array(buffer.readableBytesView.prefix(8)) == [0, 3, 0, 0, 0x3F, 0x80, 0, 0])
        #expect(try Vector<3>(from: &buffer, type: .text, format: .binary, context: .default) == vector)

        let half = try HalfVector<3>([1, -2.5, 0.000_1])
        var halfBuffer = ByteBuffer()
        half.encode(into: &halfBuffer, context: .default)
        #expect(Array(halfBuffer.readableBytesView) == [0, 3, 0, 0, 0x3C, 0x00, 0xC1, 0x00, 0x06, 0x8E])
        let decoded = try HalfVector<3>(from: &halfBuffer, type: .text, format: .binary, context: .default)
        #expect(decoded.values[0] == 1 && decoded.values[1] == -2.5 && abs(decoded.values[2] - 0.000_1) < 1e-6)

        var text = ByteBuffer(string: "[1,2,3]")
        #expect(try Vector<3>(from: &text, type: .text, format: .text, context: .default).values == [1, 2, 3])
        #expect(throws: DBKitError.self) { try Vector<3>([1, 2]) }
        #expect(throws: DBKitError.self) { try HalfVector<1>([70_000]) }
    }

    /// The decoder tests inside rust-dbkit's `sparse_vector.rs` and `bit.rs`. A `sparsevec` is int32 dimensions,
    /// int32 entry count, int32 unused, the zero-based int32 indices, then the float4 values. A `bit` is its int32
    /// length, then the bits packed from the most significant, with zeros after the last bit.
    @Test func sparseAndBitBinaryFormatsRoundTripAndValidate() throws {
        let sparseBytes: [UInt8] = [0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0x3F, 0x80, 0, 0]
        let sparse = try SparseVector<3>([(2, 1)])
        #expect(try wireBytes(sparse) == sparseBytes)
        #expect(try decodeBinary(sparseBytes, as: SparseVector<3>.self) == sparse)
        for end in 0..<sparseBytes.count {
            #expect(throws: (any Error).self) { try decodeBinary(Array(sparseBytes.prefix(end)), as: SparseVector<3>.self) }
        }
        var count = sparseBytes
        count.replaceSubrange(4..<8, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: (any Error).self) { try decodeBinary(count, as: SparseVector<3>.self) }
        var index = sparseBytes
        index[15] = 3
        #expect(throws: (any Error).self) { try decodeBinary(index, as: SparseVector<3>.self) }
        #expect(throws: (any Error).self) { try decodeBinary(sparseBytes, as: SparseVector<4>.self) }

        let bitBytes: [UInt8] = [0, 0, 0, 9, 0b0100_0000, 0b1000_0000]
        let bits = try BitVector<9>([false, true, false, false, false, false, false, false, true])
        #expect(try wireBytes(bits) == bitBytes)
        #expect(try decodeBinary(bitBytes, as: BitVector<9>.self) == bits)
        for end in 0..<bitBytes.count {
            #expect(throws: (any Error).self) { try decodeBinary(Array(bitBytes.prefix(end)), as: BitVector<9>.self) }
        }
        #expect(throws: (any Error).self) { try decodeBinary(bitBytes + [0], as: BitVector<9>.self) }
        var padding = bitBytes
        padding[5] |= 1
        #expect(throws: (any Error).self) { try decodeBinary(padding, as: BitVector<9>.self) }
        #expect(throws: (any Error).self) { try decodeBinary(bitBytes, as: BitVector<8>.self) }
    }
}
