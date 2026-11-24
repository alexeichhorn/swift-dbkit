import DBKit
import Foundation

/// rust-dbkit's `CastRow`, with `Decimal` besides. `Date` stands in for its `timestamp`, `timestamptz` and `date`
/// columns; Swift has no type for its `time` columns. Waits for slice 12: `var requiredInterval: Interval` and
/// `var nullableInterval: Interval?`.
@Model(table: "cast_rows")
class CastRowModel {
    @Key var id: Int64
    var requiredBool: Bool
    var nullableBool: Bool?
    var requiredI16: Int16
    var nullableI16: Int16?
    var requiredI32: Int32
    var nullableI32: Int32?
    var requiredI64: Int64
    var nullableI64: Int64?
    var requiredF32: Float
    var nullableF32: Float?
    var requiredF64: Double
    var nullableF64: Double?
    var requiredDecimal: Decimal
    var nullableDecimal: Decimal?
    var requiredText: String
    var nullableText: String?
    var requiredUUID: UUID
    var nullableUUID: UUID?
    var requiredDate: Date
    var nullableDate: Date?
}

private typealias C = CastRowModel

// `cast(to:)` keeps nullability: a required source casts to `Expr<T>`, a nullable one to `Expr<T?>`.

// PostgreSQL casts between every built-in numeric type.
private func numericCasts() {
    let _: Expr<Int16> = C.requiredI16.cast(to: Int16.self)
    let _: Expr<Int16?> = C.nullableI16.cast(to: Int16.self)
    let _: Expr<Int32> = C.requiredI16.cast(to: Int32.self)
    let _: Expr<Int32?> = C.nullableI16.cast(to: Int32.self)
    let _: Expr<Int64> = C.requiredI16.cast(to: Int64.self)
    let _: Expr<Int64?> = C.nullableI16.cast(to: Int64.self)
    let _: Expr<Float> = C.requiredI16.cast(to: Float.self)
    let _: Expr<Float?> = C.nullableI16.cast(to: Float.self)
    let _: Expr<Double> = C.requiredI16.cast(to: Double.self)
    let _: Expr<Double?> = C.nullableI16.cast(to: Double.self)
    let _: Expr<Decimal> = C.requiredI16.cast(to: Decimal.self)
    let _: Expr<Decimal?> = C.nullableI16.cast(to: Decimal.self)

    let _: Expr<Int16> = C.requiredI32.cast(to: Int16.self)
    let _: Expr<Int16?> = C.nullableI32.cast(to: Int16.self)
    let _: Expr<Int32> = C.requiredI32.cast(to: Int32.self)
    let _: Expr<Int32?> = C.nullableI32.cast(to: Int32.self)
    let _: Expr<Int64> = C.requiredI32.cast(to: Int64.self)
    let _: Expr<Int64?> = C.nullableI32.cast(to: Int64.self)
    let _: Expr<Float> = C.requiredI32.cast(to: Float.self)
    let _: Expr<Float?> = C.nullableI32.cast(to: Float.self)
    let _: Expr<Double> = C.requiredI32.cast(to: Double.self)
    let _: Expr<Double?> = C.nullableI32.cast(to: Double.self)
    let _: Expr<Decimal> = C.requiredI32.cast(to: Decimal.self)
    let _: Expr<Decimal?> = C.nullableI32.cast(to: Decimal.self)

    let _: Expr<Int16> = C.requiredI64.cast(to: Int16.self)
    let _: Expr<Int16?> = C.nullableI64.cast(to: Int16.self)
    let _: Expr<Int32> = C.requiredI64.cast(to: Int32.self)
    let _: Expr<Int32?> = C.nullableI64.cast(to: Int32.self)
    let _: Expr<Int64> = C.requiredI64.cast(to: Int64.self)
    let _: Expr<Int64?> = C.nullableI64.cast(to: Int64.self)
    let _: Expr<Float> = C.requiredI64.cast(to: Float.self)
    let _: Expr<Float?> = C.nullableI64.cast(to: Float.self)
    let _: Expr<Double> = C.requiredI64.cast(to: Double.self)
    let _: Expr<Double?> = C.nullableI64.cast(to: Double.self)
    let _: Expr<Decimal> = C.requiredI64.cast(to: Decimal.self)
    let _: Expr<Decimal?> = C.nullableI64.cast(to: Decimal.self)

    let _: Expr<Int16> = C.requiredF32.cast(to: Int16.self)
    let _: Expr<Int16?> = C.nullableF32.cast(to: Int16.self)
    let _: Expr<Int32> = C.requiredF32.cast(to: Int32.self)
    let _: Expr<Int32?> = C.nullableF32.cast(to: Int32.self)
    let _: Expr<Int64> = C.requiredF32.cast(to: Int64.self)
    let _: Expr<Int64?> = C.nullableF32.cast(to: Int64.self)
    let _: Expr<Float> = C.requiredF32.cast(to: Float.self)
    let _: Expr<Float?> = C.nullableF32.cast(to: Float.self)
    let _: Expr<Double> = C.requiredF32.cast(to: Double.self)
    let _: Expr<Double?> = C.nullableF32.cast(to: Double.self)
    let _: Expr<Decimal> = C.requiredF32.cast(to: Decimal.self)
    let _: Expr<Decimal?> = C.nullableF32.cast(to: Decimal.self)

    let _: Expr<Int16> = C.requiredF64.cast(to: Int16.self)
    let _: Expr<Int16?> = C.nullableF64.cast(to: Int16.self)
    let _: Expr<Int32> = C.requiredF64.cast(to: Int32.self)
    let _: Expr<Int32?> = C.nullableF64.cast(to: Int32.self)
    let _: Expr<Int64> = C.requiredF64.cast(to: Int64.self)
    let _: Expr<Int64?> = C.nullableF64.cast(to: Int64.self)
    let _: Expr<Float> = C.requiredF64.cast(to: Float.self)
    let _: Expr<Float?> = C.nullableF64.cast(to: Float.self)
    let _: Expr<Double> = C.requiredF64.cast(to: Double.self)
    let _: Expr<Double?> = C.nullableF64.cast(to: Double.self)
    let _: Expr<Decimal> = C.requiredF64.cast(to: Decimal.self)
    let _: Expr<Decimal?> = C.nullableF64.cast(to: Decimal.self)

    let _: Expr<Int16> = C.requiredDecimal.cast(to: Int16.self)
    let _: Expr<Int16?> = C.nullableDecimal.cast(to: Int16.self)
    let _: Expr<Int32> = C.requiredDecimal.cast(to: Int32.self)
    let _: Expr<Int32?> = C.nullableDecimal.cast(to: Int32.self)
    let _: Expr<Int64> = C.requiredDecimal.cast(to: Int64.self)
    let _: Expr<Int64?> = C.nullableDecimal.cast(to: Int64.self)
    let _: Expr<Float> = C.requiredDecimal.cast(to: Float.self)
    let _: Expr<Float?> = C.nullableDecimal.cast(to: Float.self)
    let _: Expr<Double> = C.requiredDecimal.cast(to: Double.self)
    let _: Expr<Double?> = C.nullableDecimal.cast(to: Double.self)
    let _: Expr<Decimal> = C.requiredDecimal.cast(to: Decimal.self)
    let _: Expr<Decimal?> = C.nullableDecimal.cast(to: Decimal.self)
}

// PostgreSQL's cast between `boolean` and an integer exists for `integer` only.
private func booleanIntegerCasts() {
    let _: Expr<Bool> = C.requiredI32.cast(to: Bool.self)
    let _: Expr<Bool?> = C.nullableI32.cast(to: Bool.self)
    let _: Expr<Int32> = C.requiredBool.cast(to: Int32.self)
    let _: Expr<Int32?> = C.nullableBool.cast(to: Int32.self)
}

// A cast from text runs the target type's input function.
private func textInputCasts() {
    let _: Expr<Bool> = C.requiredText.cast(to: Bool.self)
    let _: Expr<Bool?> = C.nullableText.cast(to: Bool.self)
    let _: Expr<Int16> = C.requiredText.cast(to: Int16.self)
    let _: Expr<Int16?> = C.nullableText.cast(to: Int16.self)
    let _: Expr<Int32> = C.requiredText.cast(to: Int32.self)
    let _: Expr<Int32?> = C.nullableText.cast(to: Int32.self)
    let _: Expr<Int64> = C.requiredText.cast(to: Int64.self)
    let _: Expr<Int64?> = C.nullableText.cast(to: Int64.self)
    let _: Expr<Float> = C.requiredText.cast(to: Float.self)
    let _: Expr<Float?> = C.nullableText.cast(to: Float.self)
    let _: Expr<Double> = C.requiredText.cast(to: Double.self)
    let _: Expr<Double?> = C.nullableText.cast(to: Double.self)
    let _: Expr<Decimal> = C.requiredText.cast(to: Decimal.self)
    let _: Expr<Decimal?> = C.nullableText.cast(to: Decimal.self)
    let _: Expr<UUID> = C.requiredText.cast(to: UUID.self)
    let _: Expr<UUID?> = C.nullableText.cast(to: UUID.self)
    let _: Expr<Date> = C.requiredText.cast(to: Date.self)
    let _: Expr<Date?> = C.nullableText.cast(to: Date.self)
    // Waits for slice 12: `C.requiredText.cast(to: Interval.self)` is `Expr<Interval>`, and `Expr<Interval?>` from
    // `nullableText`.
}

// Every scalar type casts to text through its output function.
private func textOutputCasts() {
    let _: Expr<String> = C.requiredBool.cast(to: String.self)
    let _: Expr<String?> = C.nullableBool.cast(to: String.self)
    let _: Expr<String> = C.requiredI16.cast(to: String.self)
    let _: Expr<String?> = C.nullableI16.cast(to: String.self)
    let _: Expr<String> = C.requiredI32.cast(to: String.self)
    let _: Expr<String?> = C.nullableI32.cast(to: String.self)
    let _: Expr<String> = C.requiredI64.cast(to: String.self)
    let _: Expr<String?> = C.nullableI64.cast(to: String.self)
    let _: Expr<String> = C.requiredF32.cast(to: String.self)
    let _: Expr<String?> = C.nullableF32.cast(to: String.self)
    let _: Expr<String> = C.requiredF64.cast(to: String.self)
    let _: Expr<String?> = C.nullableF64.cast(to: String.self)
    let _: Expr<String> = C.requiredDecimal.cast(to: String.self)
    let _: Expr<String?> = C.nullableDecimal.cast(to: String.self)
    let _: Expr<String> = C.requiredText.cast(to: String.self)
    let _: Expr<String?> = C.nullableText.cast(to: String.self)
    let _: Expr<String> = C.requiredUUID.cast(to: String.self)
    let _: Expr<String?> = C.nullableUUID.cast(to: String.self)
    let _: Expr<String> = C.requiredDate.cast(to: String.self)
    let _: Expr<String?> = C.nullableDate.cast(to: String.self)
    // Waits for slice 12: `C.requiredInterval.cast(to: String.self)` is `Expr<String>`, and `Expr<String?>` from
    // `nullableInterval`.
}

// rust-dbkit's casts among `timestamp`, `timestamptz` and `date` are one cast from `Date` to `Date` here.
private func temporalCasts() {
    let _: Expr<Date> = C.requiredDate.cast(to: Date.self)
    let _: Expr<Date?> = C.nullableDate.cast(to: Date.self)
}
