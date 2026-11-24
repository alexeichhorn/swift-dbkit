import DBKit

// rust-dbkit's `pass_unicode_character_func_api.rs`. Each result is nullable when its argument is.

private typealias U = UnicodeSampleModel

private func unicodeFunctionsKeepTheNullabilityOfTheirArgument() {
    let _: Expr<String> = SQL.normalize(U.text, .nfc)
    let _: Expr<String?> = SQL.normalize(U.nullableText, .nfd)
    let _: Expr<String> = SQL.normalize("①", .nfkc)
    let _: Expr<String> = SQL.normalize(SQL.lower(U.text), .nfkd)
    let _: Expr<Int32> = SQL.firstCodepoint(U.text)
    let _: Expr<Int32?> = SQL.firstCodepoint(U.nullableText)
    let _: Expr<String> = SQL.fromCodepoint(U.codepoint)
    let _: Expr<String?> = SQL.fromCodepoint(U.nullableCodepoint)
    let _: Expr<String> = SQL.toASCII(U.text)
    let _: Expr<String?> = SQL.toASCII(U.nullableText)
    let _: Expr<String> = SQL.caseFold(U.text)
    let _: Expr<String?> = SQL.caseFold(U.nullableText)
    let _: Expr<Bool> = SQL.isUnicodeAssigned(U.text)
    let _: Expr<Bool?> = SQL.isUnicodeAssigned(U.nullableText)
}

private func nestedUnicodeFunctionsComposeInQueries() {
    let normalized: Expr<String?> = SQL.normalize(SQL.caseFold(U.nullableText), .nfc)
    let first: Expr<Int32?> = SQL.firstCodepoint(normalized)

    _ = U.query()
        .select(normalized.as("normalized"), first.as("first"), SQL.fromCodepoint(first).as("round_trip"))
        .filter(SQL.isUnicodeAssigned(normalized) == true)
        .orderBy(SQL.caseFold(normalized).asc)
}
