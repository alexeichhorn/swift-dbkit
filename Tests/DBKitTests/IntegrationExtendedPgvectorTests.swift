import DBKit
import Testing

/// rust-dbkit's `Embedding` of `integration_extended_pgvector.rs`.
@Model(table: "extended_embeddings")
class ExtendedEmbeddingModel {
    @Key var id: Int64
    var half: HalfVector<3>
    var sparse: SparseVector<1000>
    var bits: BitVector<9>
    var optionalHalf: HalfVector<3>?
    var optionalSparse: SparseVector<1000>?
    var optionalBits: BitVector<9>?
}

@Suite struct IntegrationExtendedPgvectorTests {
    @Test func extendedVectorsRoundtripInsertUpdateEqualityAndNulls() async throws {
        try await ensureVectorExtension()
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let half = try HalfVector<3>([0.1, 0.5, -0.25])
            let sparse = try SparseVector<1000>([(999, -0.25), (0, 0.5)])
            let bits = try BitVector<9>([false, true, false, false, false, false, false, false, true])

            let inserted = try #require(
                try await ExtendedEmbeddingModel.insert(
                    ExtendedEmbeddingModel.Insert(
                        id: 1, half: half, sparse: sparse, bits: bits, optionalHalf: half, optionalSparse: sparse, optionalBits: bits)
                )
                .returningAll()
                .first(on: tx))
            #expect(inserted.half == half)
            #expect(inserted.sparse == sparse)
            #expect(inserted.bits == bits)
            #expect(inserted.optionalHalf == half)
            #expect(inserted.optionalSparse == sparse)
            #expect(inserted.optionalBits == bits)

            let stored = try #require(
                try await tx.query("SELECT half::text, sparse::text, bits::text FROM extended_embeddings WHERE id = 1").collect().first?
                    .decode((String, String, String).self))
            #expect(try decodeText(stored.0, as: HalfVector<3>.self) == half)
            #expect(stored.1 == "{1:0.5,1000:-0.25}/1000")
            #expect(stored.2 == "010000001")

            let found = try #require(
                try await ExtendedEmbeddingModel.query()
                    .filter(ExtendedEmbeddingModel.half == half)
                    .filter(ExtendedEmbeddingModel.sparse == sparse)
                    .filter(ExtendedEmbeddingModel.bits == bits)
                    .first(on: tx))
            #expect(found.id == 1)

            let replacementHalf = try HalfVector<3>([0, 1, 0])
            let replacementSparse = try SparseVector<1000>([])
            let replacementBits = try BitVector<9>(Array(repeating: false, count: 9))
            try await ExtendedEmbeddingModel.update()
                .set(ExtendedEmbeddingModel.half, to: replacementHalf)
                .set(ExtendedEmbeddingModel.sparse, to: replacementSparse)
                .set(ExtendedEmbeddingModel.bits, to: replacementBits)
                .filter(ExtendedEmbeddingModel.id == 1)
                .execute(on: tx)
            let updated = try #require(try await ExtendedEmbeddingModel.query().filter(ExtendedEmbeddingModel.id == 1).first(on: tx))
            #expect(updated.half == replacementHalf)
            #expect(updated.sparse == replacementSparse)
            #expect(updated.bits == replacementBits)

            var active = updated.active()
            active.optionalHalf = nil
            active.optionalSparse = nil
            active.optionalBits = nil
            let cleared = try await active.update(on: tx)
            #expect(cleared.optionalHalf == nil)
            #expect(cleared.optionalSparse == nil)
            #expect(cleared.optionalBits == nil)
            let nullRows = try await ExtendedEmbeddingModel.query()
                .filter(ExtendedEmbeddingModel.optionalHalf == nil)
                .filter(ExtendedEmbeddingModel.optionalSparse == nil)
                .filter(ExtendedEmbeddingModel.optionalBits == nil)
                .all(on: tx)
            #expect(nullRows.map(\.id) == [1])

            active = cleared.active()
            active.optionalHalf = half
            active.optionalSparse = sparse
            active.optionalBits = bits
            let restored = try await active.update(on: tx)
            #expect(restored.optionalHalf == half)
            #expect(restored.optionalSparse == sparse)
            #expect(restored.optionalBits == bits)
        }
    }

    @Test func halfDistancesMatchPostgresValuesAndRankings() async throws {
        try await checkNumericDistances(
            ExtendedEmbeddingModel.half, ExtendedEmbeddingModel.optionalHalf, query: HalfVector<3>([1, 0, 0]))
    }

    @Test func sparseDistancesMatchPostgresValuesAndRankings() async throws {
        try await checkNumericDistances(
            ExtendedEmbeddingModel.sparse, ExtendedEmbeddingModel.optionalSparse, query: SparseVector<1000>([(0, 1)]))
    }

    @Test func bitDistancesMatchPostgresValuesRankingsAndNulls() async throws {
        try await ensureVectorExtension()
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedDistances(on: tx)
            let query = try BitVector<9>([true, true, false, false, false, false, false, false, false])
            let bits = ExtendedEmbeddingModel.bits

            let cases: [(distance: Expr<Double>, expected: [Double])] = [
                (bits.hammingDistance(to: query), [0, 1, 3, 3]),
                (bits.jaccardDistance(to: query), [0, 0.5, 0.6, 1]),
            ]
            for (distance, expected) in cases {
                let rows = try await ExtendedEmbeddingModel.query()
                    .select(ExtendedEmbeddingModel.id, distance)
                    .orderBy(distance.asc)
                    .orderBy(ExtendedEmbeddingModel.id.asc)
                    .all(on: tx)
                #expect(rows.map(\.0) == [1, 2, 3, 4])
                for (row, expected) in zip(rows, expected) {
                    #expect(abs(row.1 - expected) < 1e-6, "id \(row.0): \(row.1) != \(expected)")
                }
            }

            let closest = try await ExtendedEmbeddingModel.query()
                .filter(bits.hammingDistance(to: query) < 2.0)
                .filter(bits.jaccardDistance(to: query) < 0.75)
                .orderBy(bits.hammingDistance(to: query).asc)
                .limit(2)
                .all(on: tx)
            #expect(closest.map(\.id) == [1, 2])
            for distance in [
                ExtendedEmbeddingModel.optionalBits.hammingDistance(to: query),
                ExtendedEmbeddingModel.optionalBits.jaccardDistance(to: query),
            ] {
                #expect(try await ExtendedEmbeddingModel.query().filter(distance == nil).all(on: tx).count == 4)
            }
        }
    }

    @Test func hammingDistanceDecodesAsItsExpressionType() async throws {
        let query = try BitVector<9>([true, true, false, false, false, false, false, false, false])
        #expect(try await projectSecondRowDistance(ExtendedEmbeddingModel.bits.hammingDistance(to: query)) == 1.0)
    }

    @Test func jaccardDistanceDecodesAsItsExpressionType() async throws {
        let query = try BitVector<9>([true, true, false, false, false, false, false, false, false])
        #expect(try await projectSecondRowDistance(ExtendedEmbeddingModel.bits.jaccardDistance(to: query)) == 0.5)
    }

    @Test func halfDistanceDecodesAsItsExpressionType() async throws {
        let query = try HalfVector<3>([1, 0, 0])
        #expect(try await projectSecondRowDistance(ExtendedEmbeddingModel.half.l1Distance(to: query)) == 1.0)
    }

    @Test func sparseDistanceDecodesAsItsExpressionType() async throws {
        let query = try SparseVector<1000>([(0, 1)])
        #expect(try await projectSecondRowDistance(ExtendedEmbeddingModel.sparse.l1Distance(to: query)) == 1.0)
    }

    /// Rows arrive in PostgreSQL's binary format. rust-dbkit also reads them in the text format through sqlx's
    /// simple query protocol, which PostgresNIO doesn't use; here the decoder reads what `::text` returns.
    @Test func decodersValidateDimensionsInBinaryAndTextProtocols() async throws {
        try await ensureVectorExtension()
        try await withRollback { tx in
            let halfRow = try #require(
                try await tx.query("SELECT '[0.5,1,-0.25]'::halfvec, '[0.5,1,-0.25]'::halfvec::text").collect().first)
            let half = try HalfVector<3>([0.5, 1, -0.25])
            #expect(try halfRow.decode((HalfVector<3>, String).self).0 == half)
            #expect(throws: (any Error).self) { try halfRow.decode((HalfVector<2>, String).self) }
            let halfText = try halfRow.decode((HalfVector<3>, String).self).1
            #expect(try decodeText(halfText, as: HalfVector<3>.self) == half)
            #expect(throws: (any Error).self) { try decodeText(halfText, as: HalfVector<2>.self) }

            let sparseRow = try #require(
                try await tx.query("SELECT '{1:0.5,1000:-0.25}/1000'::sparsevec, '{1:0.5,1000:-0.25}/1000'::sparsevec::text").collect()
                    .first)
            let sparse = try SparseVector<1000>([(0, 0.5), (999, -0.25)])
            #expect(try sparseRow.decode((SparseVector<1000>, String).self).0 == sparse)
            #expect(throws: (any Error).self) { try sparseRow.decode((SparseVector<999>, String).self) }
            let sparseText = try sparseRow.decode((SparseVector<1000>, String).self).1
            #expect(try decodeText(sparseText, as: SparseVector<1000>.self) == sparse)
            #expect(throws: (any Error).self) { try decodeText(sparseText, as: SparseVector<999>.self) }

            let bitRow = try #require(try await tx.query("SELECT '010000001'::bit(9), '010000001'::bit(9)::text").collect().first)
            let bits = try decodeText("010000001", as: BitVector<9>.self)
            #expect(try bitRow.decode((BitVector<9>, String).self).0 == bits)
            #expect(throws: (any Error).self) { try bitRow.decode((BitVector<8>, String).self) }
            let bitText = try bitRow.decode((BitVector<9>, String).self).1
            #expect(try decodeText(bitText, as: BitVector<9>.self) == bits)
            #expect(throws: (any Error).self) { try decodeText(bitText, as: BitVector<8>.self) }
        }
    }
}

/// rust-dbkit's `numeric_distances!`: each distance of a `halfvec` or `sparsevec` column, its values and ranking, a
/// filter on one distance ordered by another, and NULL distances for a NULL column.
private func checkNumericDistances<V: PGVectorType>(
    _ column: Column<ExtendedEmbeddingModel, V>, _ optional: Column<ExtendedEmbeddingModel, V?>, query: V
) async throws {
    try await ensureVectorExtension()
    try await withRollback { tx in
        try await setupSchema(on: tx)
        try await seedDistances(on: tx)

        let cases: [(distance: Expr<Double>, expected: [Double], descending: Bool)] = [
            (column.l2Distance(to: query), [0, 0.5.squareRoot(), 2.0.squareRoot(), 2], false),
            (column.cosineDistance(to: query), [0, 1 - 0.5.squareRoot(), 1, 2], false),
            (column.l1Distance(to: query), [0, 1, 2, 2], false),
            (column.innerProductDistance(to: query), [-1, -0.5, 0, 1], false),
            (column.innerProduct(with: query), [1, 0.5, 0, -1], true),
        ]
        for (distance, expected, descending) in cases {
            let rows = try await ExtendedEmbeddingModel.query()
                .select(ExtendedEmbeddingModel.id, distance)
                .orderBy(descending ? distance.desc : distance.asc)
                .orderBy(ExtendedEmbeddingModel.id.asc)
                .all(on: tx)
            #expect(rows.map(\.0) == [1, 2, 3, 4])
            for (row, expected) in zip(rows, expected) {
                #expect(abs(row.1 - expected) < 1e-6, "id \(row.0): \(row.1) != \(expected)")
            }
        }

        let closest = try await ExtendedEmbeddingModel.query()
            .filter(column.innerProductDistance(to: query) < -0.4)
            .orderBy(column.l2Distance(to: query).asc)
            .limit(2)
            .all(on: tx)
        #expect(closest.map(\.id) == [1, 2])

        for distance in [
            optional.l2Distance(to: query),
            optional.cosineDistance(to: query),
            optional.l1Distance(to: query),
            optional.innerProductDistance(to: query),
            optional.innerProduct(with: query),
        ] {
            #expect(try await ExtendedEmbeddingModel.query().filter(distance == nil).all(on: tx).count == 4)
        }
    }
}

/// The distance of the second seeded row, decoded as the expression's own type, so the projection can't hide a
/// mismatch between the expression type and what PostgreSQL returns.
private func projectSecondRowDistance<Value: SQLType>(_ distance: Expr<Value>) async throws -> Value {
    try await ensureVectorExtension()
    var value: Value?
    try await withRollback { tx in
        try await setupSchema(on: tx)
        try await seedDistances(on: tx)
        value = try await ExtendedEmbeddingModel.query().select(distance).filter(ExtendedEmbeddingModel.id == 2).first(on: tx)
    }
    return try #require(value, "the seeded second row")
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        """
        CREATE TEMP TABLE extended_embeddings (
            id BIGINT PRIMARY KEY, half HALFVEC(3) NOT NULL, sparse SPARSEVEC(1000) NOT NULL, bits BIT(9) NOT NULL,
            optional_half HALFVEC(3), optional_sparse SPARSEVEC(1000), optional_bits BIT(9)
        )
        """)
}

/// SQL literals keep the distance expectations independent of the encoders.
private func seedDistances(on tx: Transaction) async throws {
    try await tx.query(
        """
        INSERT INTO extended_embeddings (id, half, sparse, bits) VALUES
            (1, '[1,0,0]', '{1:1}/1000', '110000000'),
            (2, '[0.5,0.5,0]', '{1:0.5,1000:0.5}/1000', '100000000'),
            (3, '[0,1,0]', '{1000:1}/1000', '111110000'),
            (4, '[-1,0,0]', '{1:-1}/1000', '000000001')
        """)
}
