import DBKit
import Testing

/// rust-dbkit's `regex_samples` of `integration_regex_inspection.rs`.
@Model(table: "regex_samples")
class RegexSampleModel {
    @Key @AutoIncrement var id: Int64
    var label: String
    var source: String?
    var pattern: String?
}

/// rust-dbkit's `InspectionResult`. A nullable source or pattern makes every result nullable.
@Projection private struct InspectionResult: Equatable {
    let label: String
    let isMatch: Bool?
    let count: Int32?
    let position: Int32?
    let captures: RegexCaptures?
    let extract: String?
}

@Suite struct IntegrationRegexInspectionTests {
    @Test func regexInspectionFollowsPostgreSQLCoreSemantics() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let cases: [(String, String?, String?)] = [
                ("repeated", "abcabc", "abc"),
                ("overlap", "ababa", "aba"),
                ("zero_length", "abc", ""),
                ("empty", "", ""),
                ("anchors_groups", "abc", "^(a)(b)?(c)$"),
                ("alternation_unicode", "é🙂é", "🙂|界"),
                ("case_sensitive", "ABC", "abc"),
                ("no_match", "abc", "z+"),
                ("null_source", nil, "a"),
                ("null_pattern", "abc", nil),
            ]
            for (label, source, pattern) in cases {
                try await seedSample(on: tx, label: label, source: source, pattern: pattern)
            }

            let rows = try await RegexSampleModel.query()
                .select(
                    InspectionResult.columns(
                        label: RegexSampleModel.label,
                        isMatch: SQL.regexIsMatch(RegexSampleModel.source, RegexSampleModel.pattern),
                        count: SQL.regexCount(RegexSampleModel.source, RegexSampleModel.pattern),
                        position: SQL.regexPosition(RegexSampleModel.source, RegexSampleModel.pattern),
                        captures: SQL.regexCaptures(RegexSampleModel.source, RegexSampleModel.pattern),
                        extract: SQL.regexExtract(RegexSampleModel.source, RegexSampleModel.pattern)
                    )
                )
                .orderBy(RegexSampleModel.id.asc)
                .all(on: tx)

            #expect(
                rows == [
                    InspectionResult(
                        label: "repeated", isMatch: true, count: 2, position: 1, captures: RegexCaptures(["abc"]), extract: "abc"),
                    InspectionResult(
                        label: "overlap", isMatch: true, count: 1, position: 1, captures: RegexCaptures(["aba"]), extract: "aba"),
                    InspectionResult(
                        label: "zero_length", isMatch: true, count: 4, position: 1, captures: RegexCaptures([""]), extract: ""),
                    InspectionResult(label: "empty", isMatch: true, count: 1, position: 1, captures: RegexCaptures([""]), extract: ""),
                    InspectionResult(
                        label: "anchors_groups", isMatch: true, count: 1, position: 1, captures: RegexCaptures(["a", "b", "c"]),
                        extract: "abc"),
                    InspectionResult(
                        label: "alternation_unicode", isMatch: true, count: 1, position: 2, captures: RegexCaptures(["🙂"]),
                        extract: "🙂"),
                    InspectionResult(label: "case_sensitive", isMatch: false, count: 0, position: 0, captures: nil, extract: nil),
                    InspectionResult(label: "no_match", isMatch: false, count: 0, position: 0, captures: nil, extract: nil),
                    InspectionResult(label: "null_source", isMatch: nil, count: nil, position: nil, captures: nil, extract: nil),
                    InspectionResult(label: "null_pattern", isMatch: nil, count: nil, position: nil, captures: nil, extract: nil),
                ])
        }
    }

    /// No match and a NULL input give `nil`; a group that didn't participate gives a `nil` element.
    @Test func regexCaptureShapeDistinguishesSQLNullFromNullElements() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedSample(on: tx, label: "shape", source: nil, pattern: nil)

            let result = try #require(
                try await RegexSampleModel.query()
                    .select(
                        SQL.regexCaptures("foobarbeque", "barbeque").as("no_groups"),
                        SQL.regexCaptures("foobarbeque", "(bar)(.*)(beque)").as("multiple_groups"),
                        SQL.regexCaptures("foobarbeque", "(bar)(.+)?(beque)").as("optional_group"),
                        SQL.regexCaptures("abc", "z+").as("no_match"),
                        SQL.regexCaptures(RegexSampleModel.source, "a").as("null_input"),
                        SQL.regexExtract("foobarbeque", "(bar)(beque)").as("whole_extract"),
                        SQL.regexExtract("abcabc", "abc").as("first_extract")
                    )
                    .first(on: tx))

            #expect(result.0?.groups == ["barbeque"])
            #expect(result.1?.groups == ["bar", "", "beque"])
            #expect(result.2?.groups == ["bar", nil, "beque"])
            #expect(result.3 == nil)
            #expect(result.4 == nil)
            #expect(result.5 == "barbeque")
            #expect(result.6 == "abc")
        }
    }

    @Test func regexExpressionAndPatternRemainBoundValues() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedSample(on: tx, label: "bound", source: nil, pattern: nil)

            let expression = "'%_\\.*+"
            let pattern = #"^'%_\\\.\*\+$"#
            let result = try #require(
                try await RegexSampleModel.query()
                    .select(
                        SQL.regexIsMatch(expression, pattern).as("is_match"),
                        SQL.regexCount(expression, pattern).as("count"),
                        SQL.regexPosition(expression, pattern).as("position"),
                        SQL.regexCaptures(expression, pattern).as("captures"),
                        SQL.regexExtract(expression, pattern).as("extract")
                    )
                    .first(on: tx))

            #expect(result.0 == true)
            #expect(result.1 == 1)
            #expect(result.2 == 1)
            #expect(result.3?.groups == [expression])
            #expect(result.4 == expression)
        }
    }

    @Test func invalidRegexIsAPostgreSQLError() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seedSample(on: tx, label: "invalid", source: nil, pattern: nil)

            let error = try await #require(throws: PSQLError.self) {
                try await RegexSampleModel.query().select(SQL.regexIsMatch("abc", "(").as("value")).first(on: tx)
            }
            #expect(error.serverInfo?[.message]?.contains("invalid regular expression") == true)
        }
    }
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        "CREATE TEMP TABLE regex_samples (id BIGSERIAL PRIMARY KEY, label TEXT NOT NULL, source TEXT NULL, pattern TEXT NULL)")
}

private func seedSample(on tx: Transaction, label: String, source: String?, pattern: String?) async throws {
    try await RegexSampleModel.insert(RegexSampleModel.Insert(label: label, source: source, pattern: pattern)).execute(on: tx)
}
