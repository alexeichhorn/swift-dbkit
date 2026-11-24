import DBKit

// `NullabilityRowModel.requiredText` and `requiredCount` are rust-dbkit's `label` and `attempts`. rust-dbkit passes
// the values to concatenate as an array; here they are arguments.
private func compositionTakesTextAndAnIntegerIndex() {
    _ = SQL.concat(NullabilityRowModel.requiredCount)  // error: 'concat'
    _ = SQL.concatWithSeparator(Int32(1), NullabilityRowModel.requiredText)  // error: 'concatWithSeparator'
    _ = SQL.split(NullabilityRowModel.requiredCount, ",")  // error: 'split'
    _ = SQL.splitPart(NullabilityRowModel.requiredText, ",", "1")  // error: 'Int32'
}
