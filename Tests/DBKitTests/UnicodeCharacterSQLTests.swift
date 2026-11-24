import DBKit
import Testing

/// The `text_samples` table of rust-dbkit's `unicode_character_sql.rs`, with nullable `body` and `nullable_codepoint`.
@Model(table: "text_samples")
class UnicodeTextSampleModel {
    @Key var id: Int64
    var title: String
    var body: String?
    var codepoint: Int32
    var nullableCodepoint: Int32?
}

private typealias U = UnicodeTextSampleModel

@Suite struct UnicodeCharacterSQLTests {
    /// The normalization form is a keyword, not a bind.
    @Test func compilesUnicodeCharacterFunctionsWithPostgreSQLNamesAndTypes() {
        let normalizedTitle: Expr<String> = SQL.normalize(U.title, .nfc)
        let normalizedBody: Expr<String?> = SQL.normalize(U.body, .nfd)
        let compatibilityComposed: Expr<String> = SQL.normalize("①", .nfkc)
        let compatibilityDecomposed: Expr<String> = SQL.normalize(SQL.lower(U.title), .nfkd)
        let titleCodepoint: Expr<Int32> = SQL.firstCodepoint(U.title)
        let bodyCodepoint: Expr<Int32?> = SQL.firstCodepoint(U.body)
        let character: Expr<String> = SQL.fromCodepoint(U.codepoint)
        let nullableCharacter: Expr<String?> = SQL.fromCodepoint(U.nullableCodepoint)
        let asciiBody: Expr<String?> = SQL.toASCII(U.body)
        let foldedTitle: Expr<String> = SQL.caseFold(U.title)
        let assignedBody: Expr<Bool?> = SQL.isUnicodeAssigned(U.body)

        let rendered = U.query()
            .select(
                normalizedTitle.as("normalized_title"),
                normalizedBody.as("normalized_body"),
                compatibilityComposed.as("compatibility_composed"),
                compatibilityDecomposed.as("compatibility_decomposed"),
                titleCodepoint.as("title_codepoint"),
                bodyCodepoint.as("body_codepoint"),
                character.as("character"),
                nullableCharacter.as("nullable_character"),
                asciiBody.as("ascii_body"),
                foldedTitle.as("folded_title"),
                assignedBody.as("assigned_body")
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT NORMALIZE("text_samples"."title", NFC) AS "normalized_title", NORMALIZE("text_samples"."body", NFD) AS "normalized_body", NORMALIZE($1, NFKC) AS "compatibility_composed", NORMALIZE(LOWER("text_samples"."title"), NFKD) AS "compatibility_decomposed", ASCII("text_samples"."title") AS "title_codepoint", ASCII("text_samples"."body") AS "body_codepoint", CHR("text_samples"."codepoint") AS "character", CHR("text_samples"."nullable_codepoint") AS "nullable_character", TO_ASCII("text_samples"."body") AS "ascii_body", CASEFOLD("text_samples"."title") AS "folded_title", UNICODE_ASSIGNED("text_samples"."body") AS "assigned_body" FROM "text_samples""#
        )
        #expect(rendered.binds.map(\.description) == ["①"])
    }

    @Test func keepsUnicodeTextBoundWhileComposingInQueries() {
        let unsafeText = "'%_\\.*[]()"
        let rendered = U.query()
            .select(SQL.normalize(unsafeText, .nfc).as("safe_text"), SQL.fromCodepoint(Int32(39)).as("quote"))
            .filter(SQL.firstCodepoint(SQL.normalize(U.title, .nfd)) == 39)
            .filter(SQL.isUnicodeAssigned(SQL.normalize(U.body, .nfkc)) == true)
            .orderBy(SQL.caseFold(SQL.normalize(U.body, .nfkd)).asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT NORMALIZE($1, NFC) AS "safe_text", CHR($2) AS "quote" FROM "text_samples" WHERE ASCII(NORMALIZE("text_samples"."title", NFD)) = $3 AND UNICODE_ASSIGNED(NORMALIZE("text_samples"."body", NFKC)) = $4 ORDER BY CASEFOLD(NORMALIZE("text_samples"."body", NFKD)) ASC"#
        )
        #expect(rendered.binds.map(\.description) == [unsafeText, "39", "39", "true"])
        #expect(rendered.binds[1].value is Int32)
    }
}
