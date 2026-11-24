import DBKit

// rust-dbkit's macros take a bracketed list; here the values are arguments, any mix of required and nullable columns,
// expressions and strings. Swift has no counterpart for its dynamically built lists. The annotations fail to compile
// when a result type changes.

private func concatenationTakesAnyMixOfTextValues() {
    let _: Expr<String> = SQL.concat()
    let _: Expr<String> = SQL.concat(TextSampleModel.title)
    let _: Expr<String> = SQL.concat(TextSampleModel.title, TextSampleModel.body)
    let _: Expr<String> = SQL.concat(TextSampleModel.body, SQL.lower("SUFFIX"), "literal")

    let _: Expr<String> = SQL.concatWithSeparator("::")
    let _: Expr<String> = SQL.concatWithSeparator("::", TextSampleModel.title)
    let _: Expr<String> = SQL.concatWithSeparator("::", TextSampleModel.title, TextSampleModel.body, "literal")
    let _: Expr<String?> = SQL.concatWithSeparator(TextSampleModel.body, TextSampleModel.title, "literal")
}
