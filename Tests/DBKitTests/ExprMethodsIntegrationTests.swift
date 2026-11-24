import DBKit
import Foundation
import Testing

/// rust-dbkit's `method_samples` of `expr_methods_integration.rs`.
@Model(table: "method_samples")
class MethodSampleModel {
    @Key var id: Int64
    var text: String
    var optionalText: String?
    var optionalPrefix: String?
    var optionalCount: Int32?
    var optionalBool: Bool?
}

private typealias M = MethodSampleModel

/// `??` is rust-dbkit's `unwrap_or`, and with an explicit fallback also its `unwrap_or_default`.
@Suite struct ExprMethodsIntegrationTests {
    @Test func fallbacksReplaceOnlyNullAndUseRustDefaults() async throws {
        struct FallbackResult: Decodable, Equatable {
            let literal: String
            let columnFallback: String
            let expressionFallback: String
            let defaultText: String
            let defaultCount: Int32
            let defaultBool: Bool
            let computedCount: Int32
        }

        try await withRollback { tx in
            try await setup(on: tx)
            let literal: Expr<String> = M.optionalText ?? "fallback"
            let columnFallback: Expr<String> = M.optionalText ?? M.text
            let expressionFallback: Expr<String> = M.optionalText ?? M.text.lowercased()
            let defaultText: Expr<String> = M.optionalText ?? ""
            let defaultCount: Expr<Int32> = M.optionalCount ?? 0
            let defaultBool: Expr<Bool> = M.optionalBool ?? false
            let computedCount: Expr<Int32> = (M.optionalCount + 2) ?? 99
            let rows = try await M.query()
                .select(
                    literal.as("literal"),
                    columnFallback.as("column_fallback"),
                    expressionFallback.as("expression_fallback"),
                    defaultText.as("default_text"),
                    defaultCount.as("default_count"),
                    defaultBool.as("default_bool"),
                    computedCount.as("computed_count")
                )
                .orderBy(M.id.asc)
                .all(as: FallbackResult.self, on: tx)

            // `optional_count` has the SQL DEFAULT 91, which a fallback never uses.
            #expect(
                rows == [
                    FallbackResult(
                        literal: "fallback", columnFallback: "ALPHA", expressionFallback: "alpha", defaultText: "", defaultCount: 0,
                        defaultBool: false, computedCount: 99),
                    FallbackResult(
                        literal: "", columnFallback: "", expressionFallback: "", defaultText: "", defaultCount: 0, defaultBool: false,
                        computedCount: 2),
                    FallbackResult(
                        literal: "    ", columnFallback: "    ", expressionFallback: "    ", defaultText: "    ", defaultCount: -4,
                        defaultBool: true, computedCount: -2),
                    FallbackResult(
                        literal: "  ALPHA  ", columnFallback: "  ALPHA  ", expressionFallback: "  ALPHA  ", defaultText: "  ALPHA  ",
                        defaultCount: 7, defaultBool: true, computedCount: 9),
                    FallbackResult(
                        literal: "%_literal", columnFallback: "%_literal", expressionFallback: "%_literal", defaultText: "%_literal",
                        defaultCount: 2, defaultBool: false, computedCount: 4),
                    FallbackResult(
                        literal: "\tALPHA\n", columnFallback: "\tALPHA\n", expressionFallback: "\tALPHA\n", defaultText: "\tALPHA\n",
                        defaultCount: 3, defaultBool: false, computedCount: 5),
                ])

            let positive = try await M.query()
                .filter((M.optionalCount > 0) ?? false)
                .orderBy(M.id.asc)
                .all(on: tx)
            #expect(positive.map(\.id) == [4, 5, 6])
        }
    }

    /// SQL `TRIM` removes spaces, not the tabs and newlines Swift's whitespace trimming removes.
    @Test func stringChainsPreserveNullabilityAndPostgresSpaceTrimming() async throws {
        struct StringResult: Decodable, Equatable {
            let required: String
            let optional: String?
            let requiredWithOptionalPrefix: Bool?
            let optionalWithRequiredPrefix: Bool?
            let optionalWithOptionalPrefix: Bool?
        }

        try await withRollback { tx in
            try await setup(on: tx)
            let rows = try await M.query()
                .select(
                    M.text.trimmed().lowercased().as("required"),
                    M.optionalText.trimmed().lowercased().as("optional"),
                    M.text.hasPrefix(M.optionalPrefix).as("required_with_optional_prefix"),
                    M.optionalText.hasPrefix("").as("optional_with_required_prefix"),
                    M.optionalText.lowercased().hasPrefix(M.optionalPrefix.lowercased()).as("optional_with_optional_prefix")
                )
                .orderBy(M.id.asc)
                .all(as: StringResult.self, on: tx)

            #expect(
                rows == [
                    StringResult(
                        required: "alpha", optional: nil, requiredWithOptionalPrefix: nil, optionalWithRequiredPrefix: nil,
                        optionalWithOptionalPrefix: nil),
                    StringResult(
                        required: "", optional: "", requiredWithOptionalPrefix: true, optionalWithRequiredPrefix: true,
                        optionalWithOptionalPrefix: true),
                    StringResult(
                        required: "", optional: "", requiredWithOptionalPrefix: true, optionalWithRequiredPrefix: true,
                        optionalWithOptionalPrefix: true),
                    StringResult(
                        required: "alpha", optional: "alpha", requiredWithOptionalPrefix: true, optionalWithRequiredPrefix: true,
                        optionalWithOptionalPrefix: true),
                    StringResult(
                        required: "%_literal", optional: "%_literal", requiredWithOptionalPrefix: true,
                        optionalWithRequiredPrefix: true, optionalWithOptionalPrefix: true),
                    StringResult(
                        required: "\talpha\n", optional: "\talpha\n", requiredWithOptionalPrefix: true,
                        optionalWithRequiredPrefix: true, optionalWithOptionalPrefix: true),
                ])

            let normalized = M.optionalText.trimmed().lowercased() ?? ""
            let matches = try await M.query()
                .filter(normalized.hasPrefix("alpha"))
                .orderBy(normalized.asc)
                .all(on: tx)
            #expect(matches.map(\.id) == [4])
        }
    }

    /// rust-dbkit calls `starts_with` on a value turned into an expression; Swift's `String` has its own `hasPrefix`, so
    /// this calls `SQL.startsWith`.
    @Test func startsWithUsesLiteralCaseSensitivePrefixes() async throws {
        let cases: [(text: String, prefix: String, expected: Bool)] = [
            ("Alpha", "Al", true),
            ("Alpha", "al", false),
            ("", "", true),
            ("", "a", false),
            ("a", "", true),
            ("a", "ab", false),
            ("%_literal", "%_", true),
            ("anything", "%", false),
            ("anything", "_", false),
            ("'\\literal", "'\\", true),
            ("🦀café", "🦀", true),
            ("café", "caf", true),
        ]

        try await withRollback { tx in
            try await setup(on: tx)
            for (text, prefix, expected) in cases {
                let matches = try await M.query()
                    .filter(M.id == 1)
                    .select(SQL.startsWith(text, prefix).as("matches"))
                    .first(on: tx)
                #expect(matches == expected, "text: \(text.debugDescription), prefix: \(prefix.debugDescription)")
            }
        }
    }

    /// PostgreSQL sums `bigint` as `numeric`, also inside `COALESCE`.
    @Test func aggregateMethodsHandleEmptyInputsAndFilteredAggregates() async throws {
        struct AggregateResult: Decodable {
            let total: Decimal
            let defaultTotal: Decimal
            let filteredTotal: Decimal
            let firstText: String
        }

        try await withRollback { tx in
            try await setup(on: tx)
            let cases: [(minimumID: Int64, expected: (Decimal, Decimal, Decimal, String))] = [
                (0, (21, 21, 15, "")),
                (100, (42, 0, 0, "empty")),
            ]
            for (minimumID, expected) in cases {
                let result = try #require(
                    try await M.query()
                        .filter(M.id > minimumID)
                        .select(
                            (SQL.sum(M.id) ?? 42).as("total"),
                            (SQL.sum(M.id) ?? 0).as("default_total"),
                            (SQL.sum(M.id).filter(M.id > 3) ?? 0).as("filtered_total"),
                            (SQL.min(M.text).trimmed().lowercased() ?? "empty").as("first_text")
                        )
                        .first(as: AggregateResult.self, on: tx),
                    "an aggregate returns a row even without input rows")
                #expect((result.total, result.defaultTotal, result.filteredTotal, result.firstText) == expected)
            }
        }
    }
}

private func setup(on tx: Transaction) async throws {
    try await tx.query(
        """
        CREATE TEMP TABLE method_samples (
            id BIGINT PRIMARY KEY, text TEXT NOT NULL, optional_text TEXT, optional_prefix TEXT,
            optional_count INTEGER DEFAULT 91, optional_bool BOOLEAN
        )
        """)
    try await M.insert([
        M.Insert(id: 1, text: "ALPHA", optionalText: nil, optionalPrefix: nil, optionalCount: nil, optionalBool: nil),
        M.Insert(id: 2, text: "", optionalText: "", optionalPrefix: "", optionalCount: 0, optionalBool: false),
        M.Insert(id: 3, text: "    ", optionalText: "    ", optionalPrefix: " ", optionalCount: -4, optionalBool: true),
        M.Insert(id: 4, text: "  ALPHA  ", optionalText: "  ALPHA  ", optionalPrefix: "  A", optionalCount: 7, optionalBool: true),
        M.Insert(id: 5, text: "%_literal", optionalText: "%_literal", optionalPrefix: "%_", optionalCount: 2, optionalBool: false),
        M.Insert(id: 6, text: "\tALPHA\n", optionalText: "\tALPHA\n", optionalPrefix: "\tA", optionalCount: 3, optionalBool: false),
    ])
    .execute(on: tx)
}
