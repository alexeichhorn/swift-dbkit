import DBKit

// `POWER` takes numbers and `DATE_TRUNC` timestamps.
private func argumentsHaveTheFunctionsTypes() {
    _ = SQL.power(NullabilityRowModel.requiredText, 2)  // error: 'power'
    _ = SQL.power(2.0, NullabilityRowModel.nullableText)  // error: 'power'
    _ = SQL.dateTrunc(.day, NullabilityRowModel.requiredCount)  // error: 'dateTrunc'
}

// `COALESCE`, `LEAST` and `GREATEST` take arguments of one type. PostgreSQL would resolve a common type, by other rules
// than arithmetic's: `LEAST(integer, real)` is `real`.
private func fallbacksAndBoundsTakeOneType() {
    _ = SQL.coalesce(NullabilityRowModel.nullableText, NullabilityRowModel.requiredCount)  // error: 'coalesce'
    _ = SQL.least(NullabilityRowModel.requiredCount, NullabilityRowModel.id)  // error: 'least'
    _ = SQL.greatest(NullabilityRowModel.nullableCount, NullabilityRowModel.requiredText)  // error: 'greatest'
}

// `Decimal` takes a power only with a `Decimal` exponent, as it combines only with `Decimal` in arithmetic.
private func decimalPowersTakeDecimalExponents() {
    _ = SQL.power(DecimalRowModel.price, DecimalRowModel.quantity)  // error: 'power'
    _ = SQL.power(DecimalRowModel.rate, DecimalRowModel.price)  // error: 'power'
}
