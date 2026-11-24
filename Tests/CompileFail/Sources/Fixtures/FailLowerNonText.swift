import DBKit

// `NullabilityRowModel.requiredCount` is rust-dbkit's `integer` column `attempts`.
private func caseConversionTakesText() {
    _ = SQL.lower(NullabilityRowModel.requiredCount)  // error: 'lower'
    _ = SQL.trimEnd(NullabilityRowModel.requiredCount)  // error: 'trimEnd'
    _ = SQL.trimStartChars(NullabilityRowModel.requiredCount, "x")  // error: 'trimStartChars'
}
