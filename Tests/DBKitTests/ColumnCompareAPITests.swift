import DBKit
import Testing

/// rust-dbkit's `jobs` table of `column_compare_api.rs`, with nullable `embedding` and `embedding_hash`.
@Model(table: "jobs")
class JobModel {
    @Key var id: Int64
    var retryCount: Int64
    var maxRetries: Int64
    var contentHash: String
    var lastContentHash: String
    var embedding: String?
    var embeddingHash: String?
}

/// rust-dbkit's `eq_col`, `ne_col`, `lt_col`, `le_col`, `gt_col` and `ge_col` are the comparison operators between
/// two expressions; `is_distinct_from_col` and `is_not_distinct_from_col` are `isDistinct(from:)` and
/// `isNotDistinct(from:)`.
@Suite struct ColumnCompareAPITests {
    @Test func compilesNeColBetweenNonNullableColumns() {
        let predicate: Expr<Bool> = JobModel.contentHash != JobModel.lastContentHash
        let rendered = JobModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "jobs".* FROM "jobs" WHERE "jobs"."content_hash" <> "jobs"."last_content_hash""#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesLtColBetweenNumericColumns() {
        let predicate: Expr<Bool> = JobModel.retryCount < JobModel.maxRetries
        let rendered = JobModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "jobs".* FROM "jobs" WHERE "jobs"."retry_count" < "jobs"."max_retries""#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesLeColBetweenNumericColumns() {
        let predicate: Expr<Bool> = JobModel.retryCount <= JobModel.maxRetries
        let rendered = JobModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "jobs".* FROM "jobs" WHERE "jobs"."retry_count" <= "jobs"."max_retries""#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesGtColBetweenNumericColumns() {
        let predicate: Expr<Bool> = JobModel.retryCount > JobModel.maxRetries
        let rendered = JobModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "jobs".* FROM "jobs" WHERE "jobs"."retry_count" > "jobs"."max_retries""#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesGeColBetweenNumericColumns() {
        let predicate: Expr<Bool> = JobModel.retryCount >= JobModel.maxRetries
        let rendered = JobModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "jobs".* FROM "jobs" WHERE "jobs"."retry_count" >= "jobs"."max_retries""#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesNeColBetweenNullableColumns() {
        let differs: Expr<Bool?> = JobModel.embeddingHash != JobModel.embedding
        let rendered = JobModel.query().filter(differs).render()
        #expect(rendered.sql == #"SELECT "jobs".* FROM "jobs" WHERE "jobs"."embedding_hash" <> "jobs"."embedding""#)
        #expect(rendered.binds.isEmpty)

        let projected = JobModel.query().select(differs.as("differs")).render()
        #expect(projected.sql == #"SELECT "jobs"."embedding_hash" <> "jobs"."embedding" AS "differs" FROM "jobs""#)
        #expect(projected.binds.isEmpty)
    }

    @Test func compilesNullableColumnComparisonsInBooleanPredicates() {
        let predicate: Expr<Bool?> = JobModel.embeddingHash == JobModel.contentHash && JobModel.id > 0
        let rendered = JobModel.query().filter(predicate).render()
        #expect(
            rendered.sql == #"SELECT "jobs".* FROM "jobs" WHERE ("jobs"."embedding_hash" = "jobs"."content_hash" AND "jobs"."id" > $1)"#)
        #expect(rendered.binds.map(\.description) == ["0"])
    }

    @Test func compilesIsDistinctFromColBetweenNullableColumns() {
        let predicate: Expr<Bool> = JobModel.embeddingHash.isDistinct(from: JobModel.embedding)
        let rendered = JobModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "jobs".* FROM "jobs" WHERE "jobs"."embedding_hash" IS DISTINCT FROM "jobs"."embedding""#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesIsNotDistinctFromColBetweenNullableColumns() {
        let predicate: Expr<Bool> = JobModel.embeddingHash.isNotDistinct(from: JobModel.embedding)
        let rendered = JobModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "jobs".* FROM "jobs" WHERE "jobs"."embedding_hash" IS NOT DISTINCT FROM "jobs"."embedding""#)
        #expect(rendered.binds.isEmpty)
    }

    /// `??` is rust-dbkit's `func::coalesce` here.
    @Test func compilesExprNeColWithCoalesceForNullableVsNonnullable() {
        let predicate: Expr<Bool> = (JobModel.embeddingHash ?? "") != JobModel.contentHash
        let rendered = JobModel.query().filter(predicate).render()
        #expect(rendered.sql == #"SELECT "jobs".* FROM "jobs" WHERE COALESCE("jobs"."embedding_hash", $1) <> "jobs"."content_hash""#)
        #expect(rendered.binds.map(\.description) == [""])
    }

    @Test func compilesStaleEmbeddingPredicateWithNullChecksAndHashMismatch() {
        let predicate: Expr<Bool> = JobModel.embedding.isNull || JobModel.embeddingHash.isDistinct(from: JobModel.contentHash)
        let rendered = JobModel.query().filter(predicate).render()
        #expect(
            rendered.sql
                == #"SELECT "jobs".* FROM "jobs" WHERE ("jobs"."embedding" IS NULL OR "jobs"."embedding_hash" IS DISTINCT FROM "jobs"."content_hash")"#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func compilesStaleEmbeddingPredicateWithCoalesceAndHashMismatch() {
        let predicate: Expr<Bool> =
            JobModel.embedding.isNull || JobModel.embeddingHash.isNull || (JobModel.embeddingHash ?? "") != JobModel.contentHash
        let rendered = JobModel.query().filter(predicate).render()
        #expect(
            rendered.sql
                == #"SELECT "jobs".* FROM "jobs" WHERE (("jobs"."embedding" IS NULL OR "jobs"."embedding_hash" IS NULL) OR COALESCE("jobs"."embedding_hash", $1) <> "jobs"."content_hash")"#
        )
        #expect(rendered.binds.map(\.description) == [""])
    }

    @Test func compilesMixedBooleanConditionUsingColComparisonHelpers() {
        let predicate: Expr<Bool> =
            JobModel.retryCount < JobModel.maxRetries && JobModel.contentHash != JobModel.lastContentHash && JobModel.id > 0
        let rendered = JobModel.query().filter(predicate).render()
        #expect(
            rendered.sql
                == #"SELECT "jobs".* FROM "jobs" WHERE (("jobs"."retry_count" < "jobs"."max_retries" AND "jobs"."content_hash" <> "jobs"."last_content_hash") AND "jobs"."id" > $1)"#
        )
        #expect(rendered.binds.map(\.description) == ["0"])
    }
}
