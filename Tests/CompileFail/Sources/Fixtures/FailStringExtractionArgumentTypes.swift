import DBKit

// `NullabilityRowModel.requiredText` and `requiredCount` are rust-dbkit's `label` and `attempts`. Counts are `Int32`
// and fills are text.
private func extractionTakesTextAndInt32Counts() {
    _ = SQL.left(NullabilityRowModel.requiredCount, 2)  // error: 'left'
    _ = SQL.right(NullabilityRowModel.requiredText, "2")  // error: 'Int32'
    _ = SQL.substring(NullabilityRowModel.requiredText, Float(1.5), 2)  // error: 'Int32'
    _ = SQL.repeat(NullabilityRowModel.requiredText, Int64(2))  // error: 'Int32'
    _ = SQL.padStart(NullabilityRowModel.requiredText, 8, Int32(1))  // error: 'padStart'
    _ = SQL.padEnd(NullabilityRowModel.requiredText, 8, Int32(1))  // error: 'padEnd'
}
