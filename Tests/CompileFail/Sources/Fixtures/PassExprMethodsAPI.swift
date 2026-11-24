import DBKit

// `??` is rust-dbkit's `unwrap_or`. Its `unwrap_or_default` is left out, so those lines take an explicit fallback, and
// `SQL.upper(…)` stands in for its `into_expr()` where a line needs an expression rather than a column. The
// annotations fail to compile when a result type changes.

private typealias S = MethodSampleModel

private func fallbacksAreRequired() {
    let owned = "owned"
    let _: Expr<String> = S.optionalText ?? "fallback"
    let _: Expr<String> = S.optionalText ?? owned
    let _: Expr<String> = S.optionalText ?? S.text
    let _: Expr<String> = SQL.upper(S.optionalText) ?? S.text.lowercased()
    let _: Expr<Int32> = S.optionalCount ?? 0
    let _: Expr<Int32> = (S.optionalCount + 1) ?? (S.count + 2)
    let _: Expr<Bool> = S.optionalBool ?? false
    let _: Expr<Bool> = (S.optionalText == "ready") ?? false
}

private func stringMethodsKeepNullability() {
    let _: Expr<String> = S.text.trimmed()
    let _: Expr<String> = S.text.lowercased()
    let _: Expr<String> = S.text.uppercased()
    let _: Expr<String> = SQL.upper(S.text).trimmed()
    let _: Expr<String> = SQL.upper(S.text).lowercased()
    let _: Expr<String?> = S.optionalText.trimmed()
    let _: Expr<String?> = S.optionalText.lowercased()
    let _: Expr<String?> = S.optionalText.uppercased()
    let _: Expr<String?> = SQL.upper(S.optionalText).trimmed()
    let _: Expr<String?> = SQL.upper(S.optionalText).lowercased()
    let _: Expr<String?> = S.optionalText.trimmed().lowercased()
    let _: Expr<String> = (S.optionalText ?? "").trimmed().lowercased()
    let _: Expr<String> = S.optionalText.trimmed().lowercased() ?? ""

    let _: Expr<String> = SQL.lower(S.text)
    let _: Expr<String?> = SQL.upper(S.optionalText)
    let _: Expr<String?> = SQL.trim(S.optionalText)
    let _: Expr<String> = SQL.lower("MiXeD")
}

// Either nullable operand makes STARTS_WITH nullable, a nullable prefix included.
private func prefixTestsAreNullableWhenAnOperandIs() {
    let _: Expr<Bool> = S.text.hasPrefix("a")
    let _: Expr<Bool> = S.text.hasPrefix(S.prefix)
    let _: Expr<Bool?> = S.text.hasPrefix(S.optionalPrefix)
    let _: Expr<Bool?> = S.optionalText.hasPrefix(S.prefix)
    let _: Expr<Bool?> = S.optionalText.hasPrefix(S.optionalPrefix)
    let _: Expr<Bool> = S.text.lowercased().hasPrefix(S.prefix.lowercased())
    let _: Expr<Bool?> = S.text.lowercased().hasPrefix(S.optionalPrefix.lowercased())
    let _: Expr<Bool?> = S.optionalText.lowercased().hasPrefix(S.prefix.lowercased())
    let _: Expr<Bool?> = S.optionalText.lowercased().hasPrefix(S.optionalPrefix.lowercased())
    let _: Expr<Bool> = S.optionalText.trimmed().lowercased().hasPrefix("a") ?? false

    let _: Expr<Bool> = SQL.startsWith(S.text, S.prefix)
    let _: Expr<Bool?> = SQL.startsWith(S.text, S.optionalPrefix)
    let _: Expr<Bool?> = SQL.startsWith(S.optionalText, "a")
    let _: Expr<Bool> = SQL.startsWith("alpha", "a")
}

// Aggregate inputs work too; wrapping one gives a plain expression. PostgreSQL sums `integer` as `bigint`, where
// rust-dbkit types the sum `i32`.
private func methodsWrapAggregates() {
    let _: Expr<Int64> = SQL.sum(S.count) ?? 0
    let _: Expr<Int64> = SQL.sum(S.count).filter(S.count > 0) ?? 0
    let _: Expr<String?> = SQL.min(S.text).trimmed()
    let _: Expr<String?> = SQL.min(S.text).lowercased()
    let _: Expr<Bool?> = SQL.min(S.text).hasPrefix("a")
    let _: AggregateExpr<String?> = SQL.max(S.text.lowercased())
}

private func methodsComposeInQueries() {
    let normalized = S.optionalText.trimmed().lowercased() ?? ""
    _ = S.query()
        .filter(normalized.hasPrefix("a"))
        .orderBy(normalized.asc)
        .select(normalized.as("normalized"))
}
