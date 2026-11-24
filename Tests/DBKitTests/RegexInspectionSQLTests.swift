import DBKit
import Testing

/// The `text_samples` table of rust-dbkit's `regex_inspection_sql.rs`, with nullable `body` and `nullable_pattern`.
@Model(table: "text_samples")
class RegexTextSampleModel {
    @Key var id: Int64
    var title: String
    var body: String?
    var pattern: String
    var nullablePattern: String?
}

private typealias R = RegexTextSampleModel

@Suite struct RegexInspectionSQLTests {
    /// A nullable text or pattern makes the result nullable; captures and extraction are always nullable, since no
    /// match is NULL.
    @Test func compilesRegexInspectionNamesAndOutputTypes() {
        let isMatch: Expr<Bool> = SQL.regexIsMatch(R.title, R.pattern)
        let nullableMatch: Expr<Bool?> = SQL.regexIsMatch(R.body, R.pattern)
        let count: Expr<Int32> = SQL.regexCount(R.title, R.pattern)
        let nullableCount: Expr<Int32?> = SQL.regexCount(R.title, R.nullablePattern)
        let position: Expr<Int32> = SQL.regexPosition(R.title, R.pattern)
        let nullablePosition: Expr<Int32?> = SQL.regexPosition(R.body, R.nullablePattern)
        let captures: Expr<RegexCaptures?> = SQL.regexCaptures(R.title, R.pattern)
        let nullableCaptures: Expr<RegexCaptures?> = SQL.regexCaptures(R.body, R.nullablePattern)
        let extract: Expr<String?> = SQL.regexExtract(R.title, R.pattern)
        let nullableExtract: Expr<String?> = SQL.regexExtract(R.body, R.nullablePattern)

        let rendered = R.query()
            .select(
                isMatch.as("is_match"),
                nullableMatch.as("nullable_match"),
                count.as("count"),
                nullableCount.as("nullable_count"),
                position.as("position"),
                nullablePosition.as("nullable_position"),
                captures.as("captures"),
                nullableCaptures.as("nullable_captures"),
                extract.as("extract"),
                nullableExtract.as("nullable_extract")
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT REGEXP_LIKE("text_samples"."title", "text_samples"."pattern") AS "is_match", REGEXP_LIKE("text_samples"."body", "text_samples"."pattern") AS "nullable_match", REGEXP_COUNT("text_samples"."title", "text_samples"."pattern") AS "count", REGEXP_COUNT("text_samples"."title", "text_samples"."nullable_pattern") AS "nullable_count", REGEXP_INSTR("text_samples"."title", "text_samples"."pattern") AS "position", REGEXP_INSTR("text_samples"."body", "text_samples"."nullable_pattern") AS "nullable_position", REGEXP_MATCH("text_samples"."title", "text_samples"."pattern") AS "captures", REGEXP_MATCH("text_samples"."body", "text_samples"."nullable_pattern") AS "nullable_captures", REGEXP_SUBSTR("text_samples"."title", "text_samples"."pattern") AS "extract", REGEXP_SUBSTR("text_samples"."body", "text_samples"."nullable_pattern") AS "nullable_extract" FROM "text_samples""#
        )
        #expect(rendered.binds.isEmpty)
    }

    /// An extracted match is `String?`, so as a pattern it makes the position nullable.
    @Test func compilesBoundRegexesAndNestedExpressionsInQueryClauses() {
        let unsafePattern = #"^'%_\\\.\*\+$"#
        let extracted: Expr<String?> = SQL.regexExtract(SQL.lower(R.title), "[0-9]+")
        let rendered = R.query()
            .select(SQL.regexCount(SQL.trim(R.body), unsafePattern).as("count"), extracted.as("number"))
            .filter(SQL.regexIsMatch(R.title, "^(foo|bar)$") == true)
            .filter(SQL.regexPosition(R.body, extracted) > 0)
            .orderBy(SQL.regexPosition(SQL.lower(R.body), "[[:alpha:]]+").asc)
            .orderBy(SQL.regexCaptures(R.title, unsafePattern).desc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT REGEXP_COUNT(TRIM("text_samples"."body"), $1) AS "count", REGEXP_SUBSTR(LOWER("text_samples"."title"), $2) AS "number" FROM "text_samples" WHERE REGEXP_LIKE("text_samples"."title", $3) = $4 AND REGEXP_INSTR("text_samples"."body", REGEXP_SUBSTR(LOWER("text_samples"."title"), $5)) > $6 ORDER BY REGEXP_INSTR(LOWER("text_samples"."body"), $7) ASC, REGEXP_MATCH("text_samples"."title", $8) DESC"#
        )
        #expect(
            rendered.binds.map(\.description) == [
                unsafePattern, "[0-9]+", "^(foo|bar)$", "true", "[0-9]+", "0", "[[:alpha:]]+", unsafePattern,
            ])
    }

    @Test func regexMetacharactersAndSQLPunctuationRemainBindValues() {
        let expression = "'%_\\.*+); DROP TABLE text_samples; --"
        let pattern = #"^'%_\\\.\*\+\); DROP TABLE text_samples; --$"#
        let rendered = R.query()
            .select(
                SQL.regexIsMatch(expression, pattern).as("is_match"),
                SQL.regexCount(expression, pattern).as("count"),
                SQL.regexPosition(expression, pattern).as("position"),
                SQL.regexCaptures(expression, pattern).as("captures"),
                SQL.regexExtract(expression, pattern).as("extract")
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT REGEXP_LIKE($1, $2) AS "is_match", REGEXP_COUNT($3, $4) AS "count", REGEXP_INSTR($5, $6) AS "position", REGEXP_MATCH($7, $8) AS "captures", REGEXP_SUBSTR($9, $10) AS "extract" FROM "text_samples""#
        )
        #expect(rendered.binds.map(\.description) == Array(repeating: [expression, pattern], count: 5).flatMap { $0 })
    }
}
