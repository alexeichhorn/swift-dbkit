import DBKit
import Testing

@Suite struct IntegrationPgvectorTests {
    @Test func pgvectorRoundtripEqFilterAndActiveModelNulling() async throws {
        try await ensureVectorExtension()
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let embedding = try Vector<3>([0.1, 0.2, 0.3])
            let optional = try Vector<3>([0.3, 0.2, 0.1])

            let inserted = try await seedRow(on: tx, 1, "row-1", embedding, optional)
            #expect(inserted.id == 1)
            #expect(inserted.embedding == embedding)
            #expect(inserted.embeddingOptional == optional)

            let found = try #require(try await EmbeddingRowModel.query().filter(EmbeddingRowModel.embedding == embedding).first(on: tx))
            #expect(found.id == 1)

            var active = found.active()
            active.embeddingOptional = nil
            let cleared = try await active.update(on: tx)
            #expect(cleared.embeddingOptional == nil)

            let onlyNullOptional = try await EmbeddingRowModel.query().filter(EmbeddingRowModel.embeddingOptional == nil).all(on: tx)
            #expect(onlyNullOptional.map(\.id) == [1])

            let nullDistanceRows = try await EmbeddingRowModel.query()
                .filter(EmbeddingRowModel.embeddingOptional.l2Distance(to: embedding) == nil)
                .all(on: tx)
            #expect(nullDistanceRows.map(\.id) == [1])
        }
    }

    @Test func pgvectorDistanceFunctionsSupportThresholdAndOrdering() async throws {
        try await ensureVectorExtension()
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedRow(on: tx, 1, "perfect", Vector([1, 0, 0]), nil)
            try await seedRow(on: tx, 2, "close", Vector([0.9, 0.1, 0]), nil)
            try await seedRow(on: tx, 3, "far", Vector([0, 1, 0]), nil)
            let query = try Vector<3>([1, 0, 0])
            let embedding = EmbeddingRowModel.embedding

            let nearest = try await EmbeddingRowModel.query()
                .filter(embedding.l2Distance(to: query) < 1.5)
                .orderBy(embedding.l2Distance(to: query).asc)
                .all(on: tx)
            #expect(nearest.map(\.id) == [1, 2, 3])

            let highSimilarity = try await EmbeddingRowModel.query()
                .filter(embedding.cosineDistance(to: query) < 0.01)
                .filter(embedding.innerProduct(with: query) > 0.80)
                .orderBy(embedding.l1Distance(to: query).asc)
                .all(on: tx)
            #expect(highSimilarity.map(\.id) == [1, 2])
        }
    }

    @Test func pgvectorTopNByInnerProductDescReturnsExpectedRank() async throws {
        try await ensureVectorExtension()
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedRow(on: tx, 1, "perfect", Vector([1, 0, 0]), Vector([1, 0, 0]))
            try await seedRow(on: tx, 2, "close", Vector([0.9, 0.1, 0]), Vector([0.9, 0.1, 0]))
            try await seedRow(on: tx, 3, "orthogonal", Vector([0, 1, 0]), Vector([0, 1, 0]))
            try await seedRow(on: tx, 4, "opposite", Vector([-1, 0, 0]), Vector([-1, 0, 0]))
            let query = try Vector<3>([1, 0, 0])

            let top2 = try await EmbeddingRowModel.query()
                .orderBy(EmbeddingRowModel.embedding.innerProduct(with: query).desc)
                .limit(2)
                .all(on: tx)
            #expect(top2.map(\.id) == [1, 2])
        }
    }

    @Test func pgvectorTopNOptionalEmbeddingsUsesNonNullFilterForDeterminism() async throws {
        try await ensureVectorExtension()
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedRow(on: tx, 1, "has-strong-optional", Vector([0, 0, 0]), Vector([1, 0, 0]))
            try await seedRow(on: tx, 2, "missing-optional", Vector([0, 0, 0]), nil)
            try await seedRow(on: tx, 3, "has-close-optional", Vector([0, 0, 0]), Vector([0.9, 0.1, 0]))
            try await seedRow(on: tx, 4, "has-far-optional", Vector([0, 0, 0]), Vector([0, 1, 0]))
            let query = try Vector<3>([1, 0, 0])

            // The NULL filter keeps the result independent of where PostgreSQL sorts NULLs in DESC.
            let top2 = try await EmbeddingRowModel.query()
                .filter(EmbeddingRowModel.embeddingOptional.isNotNull)
                .orderBy(EmbeddingRowModel.embeddingOptional.innerProduct(with: query).desc)
                .limit(2)
                .all(on: tx)
            #expect(top2.map(\.id) == [1, 3])
        }
    }

    @Test func pgvectorTopNByInnerProductDistanceAscReturnsExpectedRank() async throws {
        try await ensureVectorExtension()
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedRow(on: tx, 1, "perfect", Vector([1, 0, 0]), nil)
            try await seedRow(on: tx, 2, "close", Vector([0.9, 0.1, 0]), nil)
            try await seedRow(on: tx, 3, "orthogonal", Vector([0, 1, 0]), nil)
            try await seedRow(on: tx, 4, "opposite", Vector([-1, 0, 0]), nil)
            let query = try Vector<3>([1, 0, 0])

            let top2 = try await EmbeddingRowModel.query()
                .orderBy(EmbeddingRowModel.embedding.innerProductDistance(to: query).asc)
                .limit(2)
                .all(on: tx)
            #expect(top2.map(\.id) == [1, 2])
        }
    }

    @Test func pgvectorInnerProductDistanceThresholdUsesNegativeInnerProductSemantics() async throws {
        try await ensureVectorExtension()
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedRow(on: tx, 1, "perfect", Vector([1, 0, 0]), nil)
            try await seedRow(on: tx, 2, "close", Vector([0.9, 0.1, 0]), nil)
            try await seedRow(on: tx, 3, "orthogonal", Vector([0, 1, 0]), nil)
            let query = try Vector<3>([1, 0, 0])

            let highlySimilar = try await EmbeddingRowModel.query()
                .filter(EmbeddingRowModel.embedding.innerProductDistance(to: query) < -0.8)
                .orderBy(EmbeddingRowModel.embedding.innerProductDistance(to: query).asc)
                .all(on: tx)
            #expect(highlySimilar.map(\.id) == [1, 2])
        }
    }
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        """
        CREATE TEMP TABLE embedding_rows (
            id BIGINT PRIMARY KEY, label TEXT NOT NULL, embedding VECTOR(3) NOT NULL, embedding_optional VECTOR(3) NULL
        )
        """)
}

@discardableResult
private func seedRow(
    on tx: Transaction, _ id: Int64, _ label: String, _ embedding: Vector<3>, _ embeddingOptional: Vector<3>?
) async throws -> EmbeddingRowModel {
    try #require(
        try await EmbeddingRowModel.insert(
            EmbeddingRowModel.Insert(id: id, label: label, embedding: embedding, embeddingOptional: embeddingOptional)
        )
        .returningAll().first(on: tx))
}
