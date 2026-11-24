import DBKit

// Two columns compare only when they hold the same type, whatever their nullability. rust-dbkit's `lt_col` and its
// `lt` with a column as the value are both `<` here.

private func comparisonsBetweenDifferentTypes() {
    _ = NullabilityRowModel.requiredText == NullabilityRowModel.nullableCount  // error: requires the types
    _ = NullabilityRowModel.nullableText != NullabilityRowModel.requiredCount  // error: requires the types
    _ = NullabilityRowModel.requiredCount < NullabilityRowModel.nullableText  // error: requires the types
    _ = (NullabilityRowModel.nullableText ?? "fallback") == NullabilityRowModel.requiredCount  // error: requires the types
    _ = NullabilityRowModel.requiredCount.isDistinct(from: NullabilityRowModel.nullableText)  // error: requires the types
    _ = NullabilityRowModel.nullableText.isNotDistinct(from: NullabilityRowModel.requiredCount)  // error: requires the types
    // Integer widths don't mix in comparisons.
    _ = NullabilityRowModel.requiredCount <= NullabilityRowModel.id  // error: requires the types
    // Waits for slice 15: `NullabilityRowModel.nullableText.lowercased() == NullabilityRowModel.requiredCount`.
}

// A comparison with a nullable column is not `Expr<Bool>`, one between required columns not `Expr<Bool?>`, and the
// NULL-safe checks are never `Expr<Bool?>`.
private func columnComparisonsKeepTheirNullability() {
    let _: Expr<Bool> = NullabilityRowModel.requiredText == NullabilityRowModel.nullableText  // error: 'Expr<Bool>'
    let _: Expr<Bool> = NullabilityRowModel.nullableCount < NullabilityRowModel.requiredCount  // error: 'Expr<Bool>'
    let _: Expr<Bool> = NullabilityRowModel.nullableCount >= NullabilityRowModel.nullableLimit  // error: 'Expr<Bool>'
    let _: Expr<Bool?> = NullabilityRowModel.requiredText != NullabilityRowModel.requiredText  // error: 'Expr<Bool?>'
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.isDistinct(from: NullabilityRowModel.nullableText)  // error: 'Expr<Bool?>'
}
