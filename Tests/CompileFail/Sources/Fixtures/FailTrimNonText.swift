import DBKit

// `NullabilityRowModel.requiredCount` is rust-dbkit's `integer` column `attempts`.
private func trimTakesText() {
    _ = SQL.trim(NullabilityRowModel.requiredCount)  // error: 'trim'
}
