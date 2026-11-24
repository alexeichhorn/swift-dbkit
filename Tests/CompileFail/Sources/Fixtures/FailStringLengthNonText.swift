import DBKit

// `NullabilityRowModel.requiredCount` is rust-dbkit's `integer` column `attempts`.
private func byteLengthTakesText() {
    _ = SQL.byteLength(NullabilityRowModel.requiredCount)  // error: 'byteLength'
}
