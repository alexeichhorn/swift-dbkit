import DBKit

// `??` is rust-dbkit's `unwrap_or`, and `(MethodSampleModel.optionalCount + 1)` stands in for its `into_expr()`.
// rust-dbkit's `unwrap_or_default` lines, and those on a pgvector column, have no counterpart here.

// Only a nullable column or expression falls back.
private func requiredExpressionsHaveNoFallback() {
    _ = MethodSampleModel.text ?? "fallback"  // error: '??'
    _ = SQL.upper(MethodSampleModel.text) ?? "fallback"  // error: '??'
}

// Only text has the string methods.
private func stringMethodsNeedText() {
    let count = MethodSampleModel.count
    _ = count.trimmed()  // error: 'trimmed
    _ = count.lowercased()  // error: 'lowercased
    _ = count.uppercased()  // error: 'uppercased
    _ = count.hasPrefix("1")  // error: 'hasPrefix
    _ = (MethodSampleModel.optionalCount + 1).trimmed()  // error: 'trimmed
    _ = (MethodSampleModel.optionalCount + 1).lowercased()  // error: 'lowercased
    _ = (MethodSampleModel.optionalCount + 1).hasPrefix("1")  // error: 'hasPrefix
}
