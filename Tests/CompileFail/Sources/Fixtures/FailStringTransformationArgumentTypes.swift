import DBKit

// `NullabilityRowModel.requiredText` and `requiredCount` are rust-dbkit's `label` and `attempts`.
private func transformationsTakeText() {
    _ = SQL.titleCase(NullabilityRowModel.requiredCount)  // error: 'titleCase'
    _ = SQL.replace(NullabilityRowModel.requiredText, NullabilityRowModel.requiredCount, "x")  // error: 'replace'
    _ = SQL.translateChars(NullabilityRowModel.requiredCount, "a", "b")  // error: 'translateChars'
}
