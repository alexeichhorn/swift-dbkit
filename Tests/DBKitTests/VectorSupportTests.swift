import DBKit
import Testing

/// This port binds a value each time it appears, where rust-dbkit binds identical values once and repeats their
/// placeholder. Both mean the same.
@Suite struct VectorSupportTests {
    @Test func queryWithPgvectorDistanceOperatorsHasExpectedSqlShape() throws {
        let query = try Vector<3>([1, 0, 0])
        let embedding = EmbeddingRowModel.embedding
        let sql = EmbeddingRowModel.query()
            .filter(embedding.l2Distance(to: query) < 0.35)
            .filter(embedding.cosineDistance(to: query) < 0.2)
            .orderBy(embedding.l2Distance(to: query).asc)
            .orderBy(embedding.cosineDistance(to: query).asc)
            .orderBy(embedding.innerProduct(with: query).asc)
            .render().sql
        #expect(
            sql
                == #"SELECT "embedding_rows".* FROM "embedding_rows" WHERE ("embedding_rows"."embedding" <-> $1::vector) < $2 AND ("embedding_rows"."embedding" <=> $3::vector) < $4 ORDER BY ("embedding_rows"."embedding" <-> $5::vector) ASC, ("embedding_rows"."embedding" <=> $6::vector) ASC, inner_product("embedding_rows"."embedding", $7::vector) ASC"#
        )
    }

    @Test func insertAndUpdateBuildersAcceptPgvectorAndOptionalPgvector() throws {
        let embedding = try Vector<3>([0.11, 0.22, 0.33])
        let replacement = try Vector<3>([0.44, 0.55, 0.66])

        let insert = EmbeddingRowModel.insert(
            EmbeddingRowModel.Insert(id: 1, label: "hello", embedding: embedding, embeddingOptional: nil)
        )
        .returningAll()
        .render()
        #expect(
            insert.sql
                == #"INSERT INTO "embedding_rows" ("id", "label", "embedding", "embedding_optional") VALUES ($1, $2, $3::vector, NULL) RETURNING *"#
        )

        let update = EmbeddingRowModel.update()
            .set(EmbeddingRowModel.embedding, to: replacement)
            .set(EmbeddingRowModel.embeddingOptional, to: embedding)
            .filter(EmbeddingRowModel.id == 1)
            .render()
        #expect(
            update.sql
                == #"UPDATE "embedding_rows" SET "embedding" = $1::vector, "embedding_optional" = $2::vector WHERE "embedding_rows"."id" = $3"#
        )
        #expect(bindValues(update) == ["[0.44,0.55,0.66]", "[0.11,0.22,0.33]", "1"])

        let clearOptional = EmbeddingRowModel.update()
            .set(EmbeddingRowModel.embeddingOptional, to: nil)
            .filter(EmbeddingRowModel.id == 1)
            .render()
        #expect(clearOptional.sql == #"UPDATE "embedding_rows" SET "embedding_optional" = NULL WHERE "embedding_rows"."id" = $1"#)
    }

    @Test func pgvectorConstructorsValidateNonFiniteInputs() {
        #expect(throws: DBKitError.self) { try Vector<3>([0, .nan, 1]) }
        #expect(throws: DBKitError.self) { try Vector<3>([0, .infinity, 1]) }
    }

    @Test func optionalPgvectorDistanceOrderingUsesOperatorSqlShape() throws {
        let query = try Vector<3>([1, 0, 0])
        let sql = EmbeddingRowModel.query()
            .filter(EmbeddingRowModel.embeddingOptional.isNotNull)
            .orderBy(EmbeddingRowModel.embeddingOptional.cosineDistance(to: query).asc)
            .limit(5)
            .render().sql
        #expect(
            sql
                == #"SELECT "embedding_rows".* FROM "embedding_rows" WHERE "embedding_rows"."embedding_optional" IS NOT NULL ORDER BY ("embedding_rows"."embedding_optional" <=> $1::vector) ASC LIMIT 5"#
        )
    }

    @Test func innerProductDistanceOrderingUsesOperatorSqlShape() throws {
        let query = try Vector<3>([0.9, 0, 0.1])
        let sql = EmbeddingRowModel.query()
            .orderBy(EmbeddingRowModel.embedding.innerProductDistance(to: query).asc)
            .limit(10)
            .render().sql
        #expect(
            sql == #"SELECT "embedding_rows".* FROM "embedding_rows" ORDER BY ("embedding_rows"."embedding" <#> $1::vector) ASC LIMIT 10"#
        )
    }
}
