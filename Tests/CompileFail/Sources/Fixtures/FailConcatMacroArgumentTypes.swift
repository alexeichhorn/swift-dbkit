import DBKit

// `NullabilityRowModel.requiredText` and `requiredCount` are rust-dbkit's `label` and `attempts`. rust-dbkit's macros
// take a bracketed list; here the values are arguments. Swift has no counterpart for its dynamically built list.
private func everyValueAndTheSeparatorAreText() {
    _ = SQL.concat(NullabilityRowModel.requiredCount)  // error: 'concat'
    _ = SQL.concat(NullabilityRowModel.requiredText, NullabilityRowModel.requiredCount)  // error: 'concat'
    _ = SQL.concatWithSeparator(NullabilityRowModel.requiredCount, NullabilityRowModel.requiredText)  // error: 'concatWithSeparator'
    _ = SQL.concatWithSeparator("::", NullabilityRowModel.requiredCount)  // error: 'concatWithSeparator'
}
