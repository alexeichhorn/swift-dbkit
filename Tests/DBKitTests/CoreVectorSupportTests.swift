import DBKit
import Testing

/// This port binds a value each time it appears, where rust-dbkit binds identical values once and repeats their
/// placeholder. Both mean the same.
@Suite struct CoreVectorSupportTests {
    @Test func pgvectorRejectsNanAndInfinity() {
        for value in [Float.nan, .infinity, -.infinity] {
            #expect(throws: DBKitError.invalidVector("vector values must be finite")) { try Vector<3>([0, value, 1]) }
        }
    }

    @Test func selectBindsPgvectorEqAndNullFilters() throws {
        let query = try Vector<3>([0.5, 0.25, 0.125])
        let rendered = EmbeddingRowModel.query()
            .filter(EmbeddingRowModel.embedding == query)
            .filter(EmbeddingRowModel.embeddingOptional == nil)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "embedding_rows".* FROM "embedding_rows" WHERE "embedding_rows"."embedding" = $1::vector AND "embedding_rows"."embedding_optional" IS NULL"#
        )
        #expect(bindValues(rendered) == ["[0.5,0.25,0.125]"])
    }

    @Test func selectCompilesVectorDistanceOperatorsAndBindOrder() throws {
        let query = try Vector<3>([1, 0, 0])
        let embedding = EmbeddingRowModel.embedding
        let rendered = EmbeddingRowModel.query()
            .filter(embedding.l2Distance(to: query) < 0.30)
            .filter(embedding.cosineDistance(to: query) < 0.20)
            .filter(embedding.innerProduct(with: query) > 0.50)
            .filter(embedding.l1Distance(to: query) < 0.80)
            .orderBy(embedding.l2Distance(to: query).asc)
            .orderBy(embedding.cosineDistance(to: query).asc)
            .orderBy(embedding.innerProduct(with: query).asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "embedding_rows".* FROM "embedding_rows" WHERE ("embedding_rows"."embedding" <-> $1::vector) < $2 AND ("embedding_rows"."embedding" <=> $3::vector) < $4 AND inner_product("embedding_rows"."embedding", $5::vector) > $6 AND ("embedding_rows"."embedding" <+> $7::vector) < $8 ORDER BY ("embedding_rows"."embedding" <-> $9::vector) ASC, ("embedding_rows"."embedding" <=> $10::vector) ASC, inner_product("embedding_rows"."embedding", $11::vector) ASC"#
        )
        let vector = "[1.0,0.0,0.0]"
        #expect(bindValues(rendered) == [vector, "0.3", vector, "0.2", vector, "0.5", vector, "0.8", vector, vector, vector])
    }

    @Test func selectCompilesInnerProductDistanceOperatorForAnnOrderBy() throws {
        let query = try Vector<3>([0.2, 0.1, 0.7])
        let rendered = EmbeddingRowModel.query()
            .orderBy(EmbeddingRowModel.embedding.innerProductDistance(to: query).asc)
            .limit(10)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "embedding_rows".* FROM "embedding_rows" ORDER BY ("embedding_rows"."embedding" <#> $1::vector) ASC LIMIT 10"#
        )
    }

    /// rust-dbkit converts a `Vec<f32>` with `TryFrom`; here `Vector(_:)` takes the array.
    @Test func pgvectorTryFromVecValidatesExactDimension() throws {
        #expect(try Vector<3>([0.1, -2, 65520]).values == [0.1, -2, 65520])

        let wrongCounts: [[Float]] = [[], [1, 2], [.nan, 2, 3, 4]]
        for values in wrongCounts {
            #expect(throws: DBKitError.invalidVector("expected 3 dimensions, got \(values.count)")) { try Vector<3>(values) }
        }
    }

    @Test func pgvectorTryFromVecPreservesFiniteValidationAndEmptyVectors() throws {
        for value in [Float.nan, .infinity, -.infinity] {
            #expect(throws: DBKitError.invalidVector("vector values must be finite")) { try Vector<3>([1, value, 2]) }
        }
        #expect(try Vector<0>([]).values.isEmpty)
    }

    @Test func selectCompilesOptionalVectorDistanceOperator() throws {
        let query = try Vector<3>([0.2, 0.3, 0.4])
        let distance: Expr<Double?> = EmbeddingRowModel.embeddingOptional.cosineDistance(to: query)
        let rendered = EmbeddingRowModel.query()
            .filter(EmbeddingRowModel.embeddingOptional.isNotNull)
            .orderBy(distance.asc)
            .limit(5)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "embedding_rows".* FROM "embedding_rows" WHERE "embedding_rows"."embedding_optional" IS NOT NULL ORDER BY ("embedding_rows"."embedding_optional" <=> $1::vector) ASC LIMIT 5"#
        )
    }
}
