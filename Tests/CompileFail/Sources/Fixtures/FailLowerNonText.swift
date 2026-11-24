import DBKit

// `NullabilityRowModel.requiredCount` is rust-dbkit's `integer` column `attempts`.
private func caseConversionTakesText() {
    _ = SQL.lower(NullabilityRowModel.requiredCount)  // error: 'lower'
    // Waits for slice 16: `SQL.trimEnd(NullabilityRowModel.requiredCount)` and
    // `SQL.trimStartChars(NullabilityRowModel.requiredCount, "x")` fail.
}
