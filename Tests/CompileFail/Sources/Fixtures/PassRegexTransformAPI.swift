import DBKit

// rust-dbkit's `pass_regex_transform_api.rs`. A nullable text, pattern or replacement makes the result nullable.
// `[]` is rust-dbkit's `empty()`.

private typealias T = TextSampleModel

private func transformsKeepTheNullabilityOfEveryArgument() {
    let allCaseInsensitive: RegexReplaceFlags = [.global, .caseInsensitive]
    let _: Expr<String> = SQL.regexReplace(T.title, "a", "x", [])
    let _: Expr<String?> = SQL.regexReplace(T.body, "a", "x", allCaseInsensitive)
    let _: Expr<String?> = SQL.regexReplace(T.title, T.body, "x", [])
    let _: Expr<String?> = SQL.regexReplace(T.title, "a", T.body, .caseInsensitive)

    let _: Expr<[String]> = SQL.regexSplit(T.title, #"\s+"#, [])
    let _: Expr<[String]?> = SQL.regexSplit(T.body, #"\s+"#, .caseInsensitive)
    let _: Expr<[String]?> = SQL.regexSplit(T.title, T.body, [])

    // Without flags a call replaces the first match and splits case-sensitively.
    let _: Expr<String> = SQL.regexReplace(T.title, "a", "x")
    let _: Expr<[String]> = SQL.regexSplit(T.title, #"\s+"#)
}

private func nestedTransformsComposeInQueries() {
    let normalized: Expr<String?> = SQL.regexReplace(
        SQL.lower(SQL.trim(SQL.substring(T.body, 1, 99))),
        SQL.lower("[A-Z]+"),
        SQL.lower("WORD"),
        [.global, .caseInsensitive]
    )
    let parts: Expr<[String]?> = SQL.regexSplit(normalized, SQL.lower(#"\s+"#), [])

    _ = T.query()
        .select(normalized.as("normalized"), parts.as("parts"))
        .filter(normalized == "word")
        .orderBy(parts.asc)
}
