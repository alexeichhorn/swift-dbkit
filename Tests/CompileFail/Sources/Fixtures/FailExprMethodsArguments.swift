import DBKit

// `??` is rust-dbkit's `unwrap_or`; `SQL.upper(…)` and arithmetic stand in for its `into_expr()`.

private func fallbacksTakeTheColumnsType() {
    _ = MethodSampleModel.optionalText ?? Int32(1)  // error: 'Int32'
    _ = (MethodSampleModel.optionalCount + 1) ?? "zero"  // error: String
}

// A nullable fallback can't make the result required.
private func nullableFallbacksStayNullable() {
    let noText: String? = nil
    let _: Expr<String> = MethodSampleModel.optionalText ?? MethodSampleModel.optionalText  // error: String?
    let _: Expr<String> = SQL.upper(MethodSampleModel.optionalText) ?? SQL.upper(MethodSampleModel.optionalText)  // error: String?
    let _: Expr<String> = MethodSampleModel.optionalText ?? noText  // error: String?
}

private func prefixesAreText() {
    _ = MethodSampleModel.text.hasPrefix(Int32(1))  // error: Int32
    _ = SQL.upper(MethodSampleModel.optionalText).hasPrefix(MethodSampleModel.count)  // error: Int32
    _ = SQL.upper(MethodSampleModel.text).hasPrefix(MethodSampleModel.optionalCount + 0)  // error: Int32
}
