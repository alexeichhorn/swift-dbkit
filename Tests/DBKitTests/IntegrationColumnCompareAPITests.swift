import DBKit
import Testing

@Model(table: "jobs_col_compare")
class JobColCompareModel {
    @Key @AutoIncrement var id: Int64
    var contentHash: String
    var lastContentHash: String
    var embeddingHash: String?
    var embedding: String?
    var retryCount: Int64
    var maxRetries: Int64
}

@Suite struct IntegrationColumnCompareAPITests {
    @Test func neColFiltersChangedHashRows() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await JobColCompareModel.insert([
                job(content: "h1", last: "h1", embeddingHash: "h1", embedding: "v1", retryCount: 0, maxRetries: 3),
                job(content: "h2", last: "h1", embeddingHash: "h1", embedding: "v2", retryCount: 1, maxRetries: 3),
            ])
            .execute(on: tx)

            let changed = try await JobColCompareModel.query()
                .filter(JobColCompareModel.contentHash != JobColCompareModel.lastContentHash)
                .all(on: tx)

            #expect(changed.count == 1)
            #expect(changed.first?.contentHash == "h2")
            #expect(changed.first?.lastContentHash == "h1")
        }
    }

    @Test func eqColAndNeColCompareRequiredAndNullableColumnsInBothDirections() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await JobColCompareModel.insert([
                job(content: "equal", last: "equal", embeddingHash: "equal", embedding: "equal"),
                job(content: "required", last: "required", embeddingHash: "different", embedding: "different"),
                job(content: "null", last: "null", embeddingHash: "null", embedding: "null"),
                job(content: "missing", last: "missing", embeddingHash: nil, embedding: nil),
            ])
            .execute(on: tx)

            let requiredToNullableEqual = try await JobColCompareModel.query()
                .filter(JobColCompareModel.contentHash == JobColCompareModel.embeddingHash)
                .orderBy(JobColCompareModel.id.asc)
                .all(on: tx)
            let nullableToRequiredEqual = try await JobColCompareModel.query()
                .filter(JobColCompareModel.embeddingHash == JobColCompareModel.contentHash)
                .orderBy(JobColCompareModel.id.asc)
                .all(on: tx)
            #expect(requiredToNullableEqual.map(\.contentHash) == ["equal", "null"])
            #expect(nullableToRequiredEqual.map(\.contentHash) == ["equal", "null"])

            let requiredToNullableDifferent = try await JobColCompareModel.query()
                .filter(JobColCompareModel.contentHash != JobColCompareModel.embeddingHash)
                .all(on: tx)
            let nullableToRequiredDifferent = try await JobColCompareModel.query()
                .filter(JobColCompareModel.embeddingHash != JobColCompareModel.contentHash)
                .all(on: tx)
            #expect(requiredToNullableDifferent.map(\.contentHash) == ["required"])
            #expect(nullableToRequiredDifferent.map(\.contentHash) == ["required"])
        }
    }

    @Test func nullableColumnComparisonProjectionsFollowPostgresThreeValuedLogic() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await JobColCompareModel.insert([
                job(content: "required", last: "equal", embeddingHash: "b", embedding: "b", retryCount: 0, maxRetries: 0),
                job(content: "required", last: "less", embeddingHash: "a", embedding: "b", retryCount: 0, maxRetries: 0),
                job(content: "required", last: "greater", embeddingHash: "b", embedding: "a", retryCount: 0, maxRetries: 0),
                job(content: "required", last: "left_null", embeddingHash: nil, embedding: "a", retryCount: 0, maxRetries: 0),
                job(content: "required", last: "right_null", embeddingHash: "a", embedding: nil, retryCount: 0, maxRetries: 0),
                job(content: "required", last: "both_null", embeddingHash: nil, embedding: nil, retryCount: 0, maxRetries: 0),
            ])
            .execute(on: tx)

            // Waits for slice 14: the projection of `lastContentHash` as `case_name` and of `==`, `!=`, `<`, `<=`, `>`, `>=`
            // (as `Bool?`), `isDistinct(from:)` and `isNotDistinct(from:)` (as `Bool`) between `embeddingHash` and
            // `embedding`, ordered by `id`: `nil` for every operator in the three NULL rows; the distinct checks true for
            // less, greater, left_null and right_null.

            let equalRows = try await JobColCompareModel.query()
                .filter(JobColCompareModel.embeddingHash == JobColCompareModel.embedding)
                .all(on: tx)
            #expect(equalRows.map(\.lastContentHash) == ["equal"])
        }
    }

    @Test func ltColAndGeColWorkForNumericColumnComparisons() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await JobColCompareModel.insert([
                job(content: "h1", last: "h1", embeddingHash: "h1", embedding: "v1", retryCount: 1, maxRetries: 3),
                job(content: "h2", last: "h2", embeddingHash: "h2", embedding: "v2", retryCount: 3, maxRetries: 3),
                job(content: "h3", last: "h3", embeddingHash: "h3", embedding: "v3", retryCount: 5, maxRetries: 3),
            ])
            .execute(on: tx)

            let retryable = try await JobColCompareModel.query()
                .filter(JobColCompareModel.retryCount < JobColCompareModel.maxRetries)
                .all(on: tx)
            #expect(retryable.map(\.contentHash) == ["h1"])

            let exhaustedOrOver = try await JobColCompareModel.query()
                .filter(JobColCompareModel.retryCount >= JobColCompareModel.maxRetries)
                .all(on: tx)
            #expect(exhaustedOrOver.count == 2)
        }
    }

    @Test func staleEmbeddingPredicateCatchesNullsAndHashMismatch() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedStaleEmbeddingRows(on: tx)

            let stale = try await JobColCompareModel.query()
                .filter(
                    JobColCompareModel.embedding.isNull || JobColCompareModel.embeddingHash.isDistinct(from: JobColCompareModel.contentHash)
                )
                .all(on: tx)

            // Every row but the fresh one.
            #expect(Set(stale.map(\.contentHash)) == ["missing-embedding", "missing-hash", "new-content"])
            #expect(stale.count == 3)
        }
    }

    /// `??` is rust-dbkit's `func::coalesce` here.
    @Test func staleEmbeddingPredicateWithCoalesceCatchesNullsAndHashMismatch() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedStaleEmbeddingRows(on: tx)

            let stale = try await JobColCompareModel.query()
                .filter(
                    JobColCompareModel.embedding.isNull || JobColCompareModel.embeddingHash.isNull
                        || (JobColCompareModel.embeddingHash ?? "") != JobColCompareModel.contentHash
                )
                .all(on: tx)

            // Every row but the fresh one.
            #expect(Set(stale.map(\.contentHash)) == ["missing-embedding", "missing-hash", "new-content"])
            #expect(stale.count == 3)
        }
    }

    @Test func isDistinctFromColMatchesNullSafeTruthTableForNullableColumns() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedTruthTableRows(on: tx)

            let rows = try await JobColCompareModel.query()
                .filter(JobColCompareModel.embeddingHash.isDistinct(from: JobColCompareModel.embedding))
                .all(on: tx)

            // Equal non-null values and two NULLs are not distinct.
            #expect(Set(rows.map(\.contentHash)) == ["diff_non_null", "null_vs_value", "value_vs_null"])
            #expect(rows.count == 3)
        }
    }

    @Test func isNotDistinctFromColMatchesNullSafeTruthTableForNullableColumns() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedTruthTableRows(on: tx)

            let rows = try await JobColCompareModel.query()
                .filter(JobColCompareModel.embeddingHash.isNotDistinct(from: JobColCompareModel.embedding))
                .all(on: tx)

            #expect(Set(rows.map(\.contentHash)) == ["eq_non_null", "null_vs_null"])
            #expect(rows.count == 2)
        }
    }
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        """
        CREATE TEMP TABLE jobs_col_compare (
            id BIGSERIAL PRIMARY KEY, content_hash TEXT NOT NULL, last_content_hash TEXT NOT NULL, embedding_hash TEXT,
            embedding TEXT, retry_count BIGINT NOT NULL, max_retries BIGINT NOT NULL
        )
        """)
}

private func job(
    content: String, last: String, embeddingHash: String?, embedding: String?, retryCount: Int64 = 0, maxRetries: Int64 = 3
) -> JobColCompareModel.Insert {
    JobColCompareModel.Insert(
        contentHash: content, lastContentHash: last, embeddingHash: embeddingHash, embedding: embedding, retryCount: retryCount,
        maxRetries: maxRetries)
}

/// A fresh row, one without an embedding, one without an embedding hash, and one whose embedding hash is stale.
private func seedStaleEmbeddingRows(on tx: Transaction) async throws {
    try await JobColCompareModel.insert([
        job(content: "fresh", last: "fresh", embeddingHash: "fresh", embedding: "vec-fresh"),
        job(content: "missing-embedding", last: "missing-embedding", embeddingHash: "missing-embedding", embedding: nil),
        job(content: "missing-hash", last: "missing-hash", embeddingHash: nil, embedding: "vec-present"),
        job(content: "new-content", last: "new-content", embeddingHash: "old-content", embedding: "vec-stale"),
    ])
    .execute(on: tx)
}

/// Each pairing of `embeddingHash` and `embedding`: equal, different, NULL on either side and NULL on both.
private func seedTruthTableRows(on tx: Transaction) async throws {
    try await JobColCompareModel.insert([
        job(content: "eq_non_null", last: "eq_non_null", embeddingHash: "same", embedding: "same"),
        job(content: "diff_non_null", last: "diff_non_null", embeddingHash: "a", embedding: "b"),
        job(content: "null_vs_value", last: "null_vs_value", embeddingHash: nil, embedding: "b"),
        job(content: "value_vs_null", last: "value_vs_null", embeddingHash: "a", embedding: nil),
        job(content: "null_vs_null", last: "null_vs_null", embeddingHash: nil, embedding: nil),
    ])
    .execute(on: tx)
}
