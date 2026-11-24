import DBKit
import Testing

/// rust-dbkit's `embeddings` table of `half_vector_queries_preserve_operators_and_nullability`.
@Model(table: "embeddings")
class HalfEmbeddingModel {
    @Key var id: Int64
    var embedding: HalfVector<3>
    var optionalEmbedding: HalfVector<3>?
}

/// rust-dbkit's `embeddings` table of `sparse_vector_queries_preserve_operators_and_nullability`.
@Model(table: "embeddings")
class SparseEmbeddingModel {
    @Key var id: Int64
    var embedding: SparseVector<1000>
    var optionalEmbedding: SparseVector<1000>?
}

/// rust-dbkit's `embeddings` table of `bit_queries_preserve_dimensions_operators_and_nullability`.
@Model(table: "embeddings")
class BitEmbeddingModel {
    @Key var id: Int64
    var bits: BitVector<9>
    var optionalBits: BitVector<9>?
}

/// rust-dbkit's `embeddings` table of `bit_bind_deduplication_includes_the_bit_length`.
@Model(table: "embeddings")
class BitLengthModel {
    @Key var id: Int64
    var shortBits: BitVector<7>
    var longBits: BitVector<8>
}

/// The smallest positive half-precision value, 2⁻²⁴.
private let smallestHalf = Float(sign: .plus, exponent: -24, significand: 1)

/// rust-dbkit takes a half vector as `f32` values or as native `f16` values. `HalfVector` takes `Float`s and rounds
/// them to half precision. Text parsing goes through the decoder of PostgreSQL's text format, where rust-dbkit parses
/// a `String`. This port binds a value each time it appears, where rust-dbkit binds identical values once and repeats
/// their placeholder. Both mean the same.
@Suite struct ExtendedVectorSupportTests {
    @Test func halfVectorTryFromF32VecRoundsAndPreservesSmallValues() throws {
        let half = try HalfVector<4>([0.1, 1 + 1.0 / 2048, 65504, smallestHalf])
        #expect(half.values == [0.099_975_585_937_5, 1, 65504, smallestHalf])
    }

    @Test func halfVectorTryFromF32VecRejectsWrongLengthsNonFiniteValuesAndOverflow() {
        let wrongCounts: [[Float]] = [[], [1], [.nan, 1, 2]]
        for values in wrongCounts {
            #expect(throws: DBKitError.invalidVector("expected 2 dimensions, got \(values.count)")) { try HalfVector<2>(values) }
        }
        for value in [Float.nan, .infinity, -.infinity] {
            #expect(throws: DBKitError.invalidVector("vector values must be finite")) { try HalfVector<2>([1, value]) }
        }
        for value: Float in [65520, -65520] {
            #expect(throws: DBKitError.invalidVector("halfvec values must be within ±65504")) { try HalfVector<2>([1, value]) }
        }
        #expect(throws: DBKitError.invalidVector("halfvec dimensions must be between 1 and 16000, got 0")) { try HalfVector<0>([]) }
        #expect(throws: DBKitError.invalidVector("halfvec dimensions must be between 1 and 16000, got 16001")) {
            try HalfVector<16_001>(Array(repeating: 0, count: 16_001))
        }
    }

    /// rust-dbkit builds the vector from native `f16` values with the bits `0x8000`, `0x0001`, `0x3c01` and `0x7bff`.
    /// As `Float`s, these half values reach PostgreSQL with the same bits.
    @Test func halfVectorTryFromNativeVecPreservesBits() throws {
        let half = try HalfVector<4>([-0.0, smallestHalf, 1 + 1.0 / 1024, 65504])
        #expect(try wireBytes(half) == [0, 4, 0, 0, 0x80, 0x00, 0x00, 0x01, 0x3C, 0x01, 0x7B, 0xFF])
    }

    /// rust-dbkit converts a `Vec<bool>` with `TryFrom`; here `BitVector(_:)` takes the array. The packed bytes follow
    /// the bit length in the binary format.
    @Test func bitsTryFromVecPreservesOrderLeadingZerosAndPadding() throws {
        let bits = try BitVector<9>([false, true, false, false, false, false, false, false, true])
        #expect(bits.values == [false, true, false, false, false, false, false, false, true])
        #expect(try wireBytes(bits) == [0, 0, 0, 9, 0b0100_0000, 0b1000_0000])
        #expect(bits.description == "010000001")
        #expect(try wireBytes(BitVector<1>([true])) == [0, 0, 0, 1, 0b1000_0000])
        #expect(try wireBytes(BitVector<8>(Array(repeating: false, count: 8))) == [0, 0, 0, 8, 0])
    }

    @Test func bitsTryFromVecRejectsWrongLengthsAndZeroDimensions() {
        let wrongCounts: [[Bool]] = [[], Array(repeating: true, count: 8), Array(repeating: true, count: 10)]
        for values in wrongCounts {
            #expect(throws: DBKitError.invalidVector("expected 9 dimensions, got \(values.count)")) { try BitVector<9>(values) }
        }
        #expect(throws: DBKitError.invalidVector("bit dimensions must be between 1 and 2147483640, got 0")) { try BitVector<0>([]) }
    }

    @Test func halfVectorRoundsBeforeUseAndPreservesNativeHalfValues() throws {
        let half = try HalfVector<3>([0.1, 1 + 1.0 / 2048, 65504])
        #expect(half.values == [0.099_975_585_937_5, 1, 65504])
        #expect(try HalfVector<3>(half.values) == half)
        #expect(try decodeText(half.description, as: HalfVector<3>.self) == half)

        let smallest = try HalfVector<1>([smallestHalf])
        #expect(smallest.values == [smallestHalf])
    }

    @Test func halfVectorRejectsNonFiniteValuesOverflowAndWrongDimensions() throws {
        for value in [Float.nan, .infinity, -.infinity, 65520, -65520] {
            #expect(throws: DBKitError.self) { try HalfVector<1>([value]) }
        }
        let native = try HalfVector<2>([1, 0])
        #expect(throws: DBKitError.self) { try HalfVector<1>([native.values[0] / native.values[1]]) }
        for text in ["[1]", "[1,2,3]", "1,2", "[1,]", "[NaN,0]", "[Infinity,0]", "[65520,0]"] {
            #expect(throws: (any Error).self, "accepted \(text)") { try decodeText(text, as: HalfVector<2>.self) }
        }
        #expect(throws: DBKitError.self) { try HalfVector<0>([]) }
    }

    /// Indices are zero-based, as in Swift arrays; PostgreSQL's text format counts from 1.
    @Test func sparseVectorNormalizesEntriesAndTranslatesPostgresIndices() throws {
        let sparse = try SparseVector<1000>([(999, -0.25), (42, 0.75), (7, 0), (8, -0.0), (0, 0.5)])
        #expect(sparse.indices == [0, 42, 999])
        #expect(sparse.values == [0.5, 0.75, -0.25])
        #expect(sparse.description == "{1:0.5,43:0.75,1000:-0.25}/1000")
        #expect(try decodeText(sparse.description, as: SparseVector<1000>.self) == sparse)
        #expect(try decodeText("{1000:-0.25,1:0.5,43:0.75}/1000", as: SparseVector<1000>.self) == sparse)

        let zero = try SparseVector<1000>([])
        #expect(zero.indices.isEmpty)
        #expect(zero.values.isEmpty)
        #expect(zero.description == "{}/1000")
        #expect(try decodeText("{}/1000", as: SparseVector<1000>.self) == zero)
    }

    /// An index is checked and a repeated index rejected before zeros are dropped. A negative index, which Rust's
    /// `usize` can't hold, is out of bounds too.
    @Test func sparseVectorRejectsAmbiguousOrInvalidEntries() {
        for value: Float in [0, 1] {
            #expect(throws: DBKitError.invalidVector("sparsevec index 3 is out of bounds for 3 dimensions")) {
                try SparseVector<3>([(3, value)])
            }
        }
        #expect(throws: DBKitError.invalidVector("sparsevec index -1 is out of bounds for 3 dimensions")) { try SparseVector<3>([(-1, 1)]) }
        let repeated: [[(index: Int, value: Float)]] = [[(0, 1), (0, 2)], [(0, 0), (0, 1)], [(0, 0), (0, -0.0)]]
        for entries in repeated {
            #expect(throws: DBKitError.invalidVector("sparsevec repeats index 0")) { try SparseVector<3>(entries) }
        }
        for value in [Float.nan, .infinity, -.infinity] {
            #expect(throws: DBKitError.invalidVector("vector values must be finite")) { try SparseVector<3>([(2, value)]) }
        }
        for text in ["{0:1}/3", "{4:1}/3", "{1:1,1:2}/3", "{1:NaN}/3", "{1:Infinity}/3", "{1:1}/4", "{1:1}", "{1}/3"] {
            #expect(throws: (any Error).self, "accepted \(text)") { try decodeText(text, as: SparseVector<3>.self) }
        }
        #expect(throws: DBKitError.invalidVector("sparsevec dimensions must be between 1 and 1000000000, got 0")) {
            try SparseVector<0>([])
        }
    }

    @Test func sparseVectorCollectionLimitCountsOnlyNonzeroEntries() throws {
        var entries = (0..<16_000).map { (index: $0, value: Float(1)) }
        entries.append((16_000, 0))
        #expect(try SparseVector<16_001>(entries).indices.count == 16_000)
        entries[16_000].value = 1
        #expect(throws: DBKitError.invalidVector("sparsevec cannot have more than 16000 nonzero entries, got 16001")) {
            try SparseVector<16_001>(entries)
        }
    }

    @Test func bitsPreserveLeadingZerosAndNonByteAlignedLengths() throws {
        let bits = try BitVector<9>([false, true, false, false, false, false, false, false, true])
        #expect(try wireBytes(bits) == [0, 0, 0, 9, 0b0100_0000, 0b1000_0000])
        #expect(bits.description == "010000001")
        #expect(try decodeText(bits.description, as: BitVector<9>.self) == bits)
        #expect(try BitVector<1>([true]).description == "1")
        #expect(try wireBytes(BitVector<8>(Array(repeating: false, count: 8))) == [0, 0, 0, 8, 0])
    }

    @Test func bitsRejectInvalidDigitsAndWrongDimensions() {
        for text in ["", "101", "10101", "1021", "true", "10 1"] {
            #expect(throws: (any Error).self, "accepted \(text)") { try decodeText(text, as: BitVector<4>.self) }
        }
        #expect(throws: DBKitError.self) { try BitVector<0>([]) }
    }

    /// The dimensions are checked before the values, so a vector too large to store throws without being built.
    @Test func constructorsEnforcePostgresStorageLimits() {
        #expect(throws: DBKitError.invalidVector("halfvec dimensions must be between 1 and 16000, got 16001")) {
            try HalfVector<16_001>(Array(repeating: 0, count: 16_001))
        }
        #expect(throws: DBKitError.invalidVector("sparsevec dimensions must be between 1 and 1000000000, got 1000000001")) {
            try SparseVector<1_000_000_001>([])
        }
        #expect(throws: DBKitError.invalidVector("sparsevec cannot have more than 16000 nonzero entries, got 16001")) {
            try SparseVector<16_001>((0..<16_001).map { (index: $0, value: Float(1)) })
        }
        #expect(throws: DBKitError.invalidVector("bit dimensions must be between 1 and 2147483640, got 2147483641")) {
            try BitVector<2_147_483_641>([])
        }
    }

    @Test func halfVectorQueriesPreserveOperatorsAndNullability() throws {
        try checkNumericVectorQueries(
            HalfEmbeddingModel.embedding, HalfEmbeddingModel.optionalEmbedding, query: HalfVector<3>([1, 0.5, 0]), cast: "halfvec")
    }

    @Test func sparseVectorQueriesPreserveOperatorsAndNullability() throws {
        try checkNumericVectorQueries(
            SparseEmbeddingModel.embedding, SparseEmbeddingModel.optionalEmbedding, query: SparseVector<1000>([(0, 1), (999, 0.5)]),
            cast: "sparsevec")
    }

    @Test func bitQueriesPreserveDimensionsOperatorsAndNullability() throws {
        let query = try decodeText("010000001", as: BitVector<9>.self)
        let (bits, optionalBits) = (BitEmbeddingModel.bits, BitEmbeddingModel.optionalBits)
        let rendered = BitEmbeddingModel.query()
            .filter(bits == query)
            .filter(optionalBits == nil)
            .orderBy(bits.hammingDistance(to: query).asc)
            .orderBy(bits.jaccardDistance(to: query).asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "embeddings".* FROM "embeddings" WHERE "embeddings"."bits" = $1::bit(9) AND "embeddings"."optional_bits" IS NULL ORDER BY ("embeddings"."bits" <~> $2::bit(9)) ASC, ("embeddings"."bits" <%> $3::bit(9)) ASC"#
        )
        #expect(bindValues(rendered) == ["010000001", "010000001", "010000001"])

        let _: Expr<Double> = bits.hammingDistance(to: query)
        let _: Expr<Double> = bits.jaccardDistance(to: query)
        let _: Expr<Double?> = optionalBits.hammingDistance(to: query)
        let _: Expr<Double?> = bits.hammingDistance(to: optionalBits)
        let _: Expr<Double?> = optionalBits.hammingDistance(to: optionalBits)
        let _: Expr<Double?> = optionalBits.jaccardDistance(to: query)
        let _: Expr<Double?> = bits.jaccardDistance(to: optionalBits)
        let _: Expr<Double?> = optionalBits.jaccardDistance(to: optionalBits)
    }

    /// Every value gets its own bind here anyway; each keeps the cast with its own bit length.
    @Test func bitBindDeduplicationIncludesTheBitLength() throws {
        let rendered = try BitLengthModel.query()
            .filter(BitLengthModel.shortBits == decodeText("1000000", as: BitVector<7>.self))
            .filter(BitLengthModel.longBits == decodeText("10000000", as: BitVector<8>.self))
            .render()
        #expect(
            rendered.sql
                == #"SELECT "embeddings".* FROM "embeddings" WHERE "embeddings"."short_bits" = $1::bit(7) AND "embeddings"."long_bits" = $2::bit(8)"#
        )
        #expect(bindValues(rendered) == ["1000000", "10000000"])
    }
}

/// rust-dbkit's `numeric_vector_queries!`: `==`, `IS NULL` and the five distances of a `halfvec` or `sparsevec`
/// column, and the nullability of each distance.
private func checkNumericVectorQueries<M: Model, V: PGVectorType>(
    _ column: Column<M, V>, _ nullable: Column<M, V?>, query: V, cast: String
) {
    let rendered = M.query()
        .filter(column == query)
        .filter(nullable == nil)
        .orderBy(column.l2Distance(to: query).asc)
        .orderBy(column.cosineDistance(to: query).asc)
        .orderBy(column.l1Distance(to: query).asc)
        .orderBy(column.innerProductDistance(to: query).asc)
        .orderBy(column.innerProduct(with: query).desc)
        .render()
    #expect(
        rendered.sql
            == #"SELECT "embeddings".* FROM "embeddings" WHERE "embeddings"."embedding" = $1::\#(cast) AND "embeddings"."optional_embedding" IS NULL ORDER BY ("embeddings"."embedding" <-> $2::\#(cast)) ASC, ("embeddings"."embedding" <=> $3::\#(cast)) ASC, ("embeddings"."embedding" <+> $4::\#(cast)) ASC, ("embeddings"."embedding" <#> $5::\#(cast)) ASC, inner_product("embeddings"."embedding", $6::\#(cast)) DESC"#
    )
    #expect(bindValues(rendered) == Array(repeating: String(describing: query), count: 6))

    let _: Expr<Double> = column.l2Distance(to: query)
    let _: Expr<Double?> = nullable.l2Distance(to: query)
    let _: Expr<Double?> = column.l2Distance(to: nullable)
    let _: Expr<Double?> = nullable.l2Distance(to: nullable)
    let _: Expr<Double> = column.cosineDistance(to: query)
    let _: Expr<Double?> = nullable.cosineDistance(to: query)
    let _: Expr<Double?> = column.cosineDistance(to: nullable)
    let _: Expr<Double?> = nullable.cosineDistance(to: nullable)
    let _: Expr<Double> = column.l1Distance(to: query)
    let _: Expr<Double?> = nullable.l1Distance(to: query)
    let _: Expr<Double?> = column.l1Distance(to: nullable)
    let _: Expr<Double?> = nullable.l1Distance(to: nullable)
    let _: Expr<Double> = column.innerProductDistance(to: query)
    let _: Expr<Double?> = nullable.innerProductDistance(to: query)
    let _: Expr<Double?> = column.innerProductDistance(to: nullable)
    let _: Expr<Double?> = nullable.innerProductDistance(to: nullable)
    let _: Expr<Double> = column.innerProduct(with: query)
    let _: Expr<Double?> = nullable.innerProduct(with: query)
    let _: Expr<Double?> = column.innerProduct(with: nullable)
    let _: Expr<Double?> = nullable.innerProduct(with: nullable)
}
