import DBKit

// rust-dbkit's `pass_regex_inspection_api.rs`. A nullable text or pattern makes the result nullable; captures and
// extraction are always nullable, since no match is NULL.

private typealias R = RegexSampleModel

private func inspectionKeepsTheNullabilityOfEveryArgument() {
    let _: Expr<Bool> = SQL.regexIsMatch(R.source, R.pattern)
    let _: Expr<Bool?> = SQL.regexIsMatch(R.nullableSource, R.pattern)
    let _: Expr<Bool?> = SQL.regexIsMatch(R.source, R.nullablePattern)
    let _: Expr<Bool?> = SQL.regexIsMatch(R.nullableSource, R.nullablePattern)

    let _: Expr<Int32> = SQL.regexCount(R.source, "a+")
    let _: Expr<Int32?> = SQL.regexCount(R.nullableSource, SQL.lower(R.pattern))
    let _: Expr<Int32> = SQL.regexPosition(SQL.lower(R.source), R.pattern)
    let _: Expr<Int32?> = SQL.regexPosition(R.source, R.nullablePattern)

    let _: Expr<RegexCaptures?> = SQL.regexCaptures(R.source, "(a)(b)?")
    let _: Expr<RegexCaptures?> = SQL.regexCaptures(R.nullableSource, R.nullablePattern)
    let _: Expr<String?> = SQL.regexExtract(R.source, R.pattern)
    let _: Expr<String?> = SQL.regexExtract(R.nullableSource, R.nullablePattern)
}

private func nestedInspectionComposesInQueries() {
    let extractedPattern = SQL.regexExtract(SQL.lower(R.source), "[a-z]+")
    let nestedMatch: Expr<Bool?> = SQL.regexIsMatch(R.nullableSource, extractedPattern)
    let nestedPosition: Expr<Int32?> = SQL.regexPosition(R.nullableSource, extractedPattern)
    let nestedCaptures: Expr<RegexCaptures?> = SQL.regexCaptures(R.nullableSource, extractedPattern)

    _ = R.query()
        .select(
            nestedMatch.as("nested_match"),
            nestedPosition.as("nested_position"),
            nestedCaptures.as("nested_captures"),
            SQL.regexExtract(R.source, "^.+$").as("extract")
        )
        .filter(nestedMatch == true)
        .filter(SQL.regexCount(R.source, "[0-9]") > 0)
        .orderBy(nestedPosition.asc)
        .orderBy(SQL.regexExtract(R.nullableSource, ".+").desc)
}
