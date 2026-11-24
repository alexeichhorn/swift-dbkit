import DBKit
import Testing

/// rust-dbkit's `unicode_character_samples` of `integration_unicode_character.rs`.
@Model(table: "unicode_character_samples")
class UnicodeCharacterSampleModel {
    @Key @AutoIncrement var id: Int64
    var label: String
    var value: String
    var nullableValue: String?
    var codepoint: Int32
    var nullableCodepoint: Int32?
}

/// rust-dbkit's `Postgres18Result`.
@Projection private struct Postgres18Result: Equatable {
    let label: String
    let folded: String
    let normalizedFold: String
    let assigned: Bool
}

/// `TO_ASCII` removes accents only in these database encodings.
private let toASCIIEncodings = ["LATIN1", "LATIN2", "LATIN9", "WIN1250"]

@Suite struct IntegrationUnicodeCharacterTests {
    @Test func normalizationAndCodepointConversionFollowPostgreSQLUnicodeSemantics() async throws {
        try await withRollback { tx in
            #expect(try await serverEncoding(on: tx) == "UTF8")
            try await setupSchema(on: tx)
            try await seed(on: tx, label: "row", value: "A", nullableValue: nil, codepoint: 65, nullableCodepoint: nil)

            let normalizations: [(String, NormalizationForm, String)] = [
                ("e\u{301}", .nfc, "é"),
                ("é", .nfd, "e\u{301}"),
                ("①", .nfkc, "1"),
                ("ﬁ", .nfkd, "fi"),
                ("", .nfc, ""),
                ("already normalized", .nfc, "already normalized"),
                ("'%_\\.*[]()", .nfc, "'%_\\.*[]()"),
            ]
            for (input, form, expected) in normalizations {
                let value = try await UnicodeCharacterSampleModel.query().select(SQL.normalize(input, form).as("value")).first(on: tx)
                // `String` compares canonically equivalent strings as equal, so compare the scalars.
                #expect(value.map { Array($0.unicodeScalars) } == Array(expected.unicodeScalars), "input: \(input)")
            }

            for (input, expected) in [("A", 65), ("🦀", 0x1f980), (" ", 32), ("", 0)] as [(String, Int32)] {
                let value = try await UnicodeCharacterSampleModel.query().select(SQL.firstCodepoint(input).as("value")).first(on: tx)
                #expect(value == expected, "input: \(input)")
            }

            for (input, expected) in [(65, "A"), (0x1f980, "🦀")] as [(Int32, String)] {
                let value = try await UnicodeCharacterSampleModel.query().select(SQL.fromCodepoint(input).as("value")).first(on: tx)
                #expect(value == expected, "codepoint: \(input)")
            }

            let nulls = try #require(
                try await UnicodeCharacterSampleModel.query()
                    .select(
                        SQL.normalize(UnicodeCharacterSampleModel.nullableValue, .nfc).as("normalized"),
                        SQL.firstCodepoint(UnicodeCharacterSampleModel.nullableValue).as("first_codepoint"),
                        SQL.fromCodepoint(UnicodeCharacterSampleModel.nullableCodepoint).as("character"),
                        SQL.toASCII(UnicodeCharacterSampleModel.nullableValue).as("ascii")
                    )
                    .first(on: tx))
            #expect(nulls.0 == nil && nulls.1 == nil && nulls.2 == nil && nulls.3 == nil)
        }
    }

    @Test(arguments: [("zero", 0), ("negative", -1), ("surrogate", 0xd800), ("out of range", 0x110000)] as [(String, Int32)])
    func fromCodepointRejectsInvalidUnicodeValues(label: String, codepoint: Int32) async throws {
        try await withRollback { tx in
            #expect(try await serverEncoding(on: tx) == "UTF8")
            try await setupSchema(on: tx)
            try await seed(on: tx, label: label, value: "value", nullableValue: nil, codepoint: codepoint, nullableCodepoint: nil)

            let error = try await #require(throws: PSQLError.self) {
                try await UnicodeCharacterSampleModel.query()
                    .select(SQL.fromCodepoint(UnicodeCharacterSampleModel.codepoint).as("value"))
                    .all(on: tx)
            }
            #expect(error.serverInfo != nil, "\(label) should be rejected by PostgreSQL")
        }
    }

    @Test func toASCIIReportsUTF8AsAnUnsupportedSourceEncoding() async throws {
        try await withRollback { tx in
            #expect(try await serverEncoding(on: tx) == "UTF8")
            try await setupSchema(on: tx)
            try await seed(on: tx, label: "accented", value: "Karél", nullableValue: nil, codepoint: 65, nullableCodepoint: nil)

            let error = try await #require(throws: PSQLError.self) {
                try await UnicodeCharacterSampleModel.query().select(SQL.toASCII(UnicodeCharacterSampleModel.value).as("value")).all(on: tx)
            }
            #expect(error.serverInfo?[.message]?.contains("encoding conversion from UTF8 to ASCII not supported") == true)
        }
    }

    @Test(.enabled("requires a LATIN1, LATIN2, LATIN9 or WIN1250 database") { try await toASCIIEncodings.contains(serverEncoding()) })
    func toASCIIRemovesAccentsOnASupportedDatabaseEncoding() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            try await seed(on: tx, label: "accented", value: "Karél", nullableValue: nil, codepoint: 65, nullableCodepoint: nil)

            let value = try await UnicodeCharacterSampleModel.query()
                .select(SQL.toASCII(UnicodeCharacterSampleModel.value).as("value"))
                .first(on: tx)
            #expect(value == "Karel")
        }
    }

    @Test(.enabled("requires PostgreSQL 18 or newer") { try await serverVersionNumber() >= 180_000 })
    func postgres18CaseFoldingAndUnicodeAssignmentAreExplicitlyVersionGated() async throws {
        try await withRollback { tx in
            #expect(try await serverEncoding(on: tx) == "UTF8")
            try await setupSchema(on: tx, unicodeFast: true)
            for (label, value) in [
                ("simple", "ABC"), ("length changing", "Straße"), ("normalization", "ǰ"), ("empty", ""), ("unassigned", "\u{0378}"),
            ] {
                try await seed(on: tx, label: label, value: value, nullableValue: nil, codepoint: 65, nullableCodepoint: nil)
            }

            let rows = try await UnicodeCharacterSampleModel.query()
                .select(
                    Postgres18Result.columns(
                        label: UnicodeCharacterSampleModel.label,
                        folded: SQL.caseFold(UnicodeCharacterSampleModel.value),
                        normalizedFold: SQL.normalize(SQL.caseFold(UnicodeCharacterSampleModel.value), .nfc),
                        assigned: SQL.isUnicodeAssigned(UnicodeCharacterSampleModel.value)
                    )
                )
                .orderBy(UnicodeCharacterSampleModel.id.asc)
                .all(on: tx)
            // `String` compares canonically equivalent strings as equal, so compare the scalars of the folded values.
            #expect(rows.map(\.label) == ["simple", "length changing", "normalization", "empty", "unassigned"])
            #expect(
                rows.map { Array($0.folded.unicodeScalars) }
                    == ["abc", "strasse", "j\u{030c}", "", "\u{0378}"].map { Array($0.unicodeScalars) })
            #expect(
                rows.map { Array($0.normalizedFold.unicodeScalars) }
                    == ["abc", "strasse", "ǰ", "", "\u{0378}"].map { Array($0.unicodeScalars) })
            #expect(rows.map(\.assigned) == [true, true, true, true, false])

            let nulls = try #require(
                try await UnicodeCharacterSampleModel.query()
                    .select(
                        SQL.caseFold(UnicodeCharacterSampleModel.nullableValue).as("folded"),
                        SQL.isUnicodeAssigned(UnicodeCharacterSampleModel.nullableValue).as("assigned")
                    )
                    .orderBy(UnicodeCharacterSampleModel.id.asc)
                    .first(on: tx))
            #expect(nulls.0 == nil && nulls.1 == nil)
        }
    }
}

/// `unicodeFast` gives the text columns the `pg_unicode_fast` collation of PostgreSQL 18, which folds case by
/// Unicode's full case folding.
private func setupSchema(on tx: Transaction, unicodeFast: Bool = false) async throws {
    let valueType = unicodeFast ? "TEXT COLLATE pg_unicode_fast" : "TEXT"
    try await tx.query(
        """
        CREATE TEMP TABLE unicode_character_samples (
            id BIGSERIAL PRIMARY KEY, label TEXT NOT NULL, value \(unescaped: valueType) NOT NULL, nullable_value \(unescaped: valueType),
            codepoint INTEGER NOT NULL, nullable_codepoint INTEGER
        )
        """)
}

private func seed(
    on tx: Transaction, label: String, value: String, nullableValue: String?, codepoint: Int32, nullableCodepoint: Int32?
) async throws {
    try await UnicodeCharacterSampleModel.insert(
        UnicodeCharacterSampleModel.Insert(
            label: label, value: value, nullableValue: nullableValue, codepoint: codepoint, nullableCodepoint: nullableCodepoint)
    )
    .execute(on: tx)
}

private func serverEncoding(on executor: some DatabaseExecutor) async throws -> String {
    try await setting("server_encoding", on: executor)
}

/// For a test trait, which runs before the test's transaction.
private func serverEncoding() async throws -> String {
    try await setting("server_encoding", on: testDatabase())
}

private func serverVersionNumber() async throws -> Int {
    try await Int(setting("server_version_num", on: testDatabase()))!
}

private func setting(_ name: String, on executor: some DatabaseExecutor) async throws -> String {
    var values: [String] = []
    for try await value in try await executor.query("SELECT current_setting(\(name))").decode(String.self) {
        values.append(value)
    }
    guard let value = values.first else { throw TestDatabaseError(description: "no value for the setting \(name)") }
    return value
}
