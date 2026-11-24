import DBKit
import Foundation

/// rust-dbkit's `NullableArithmeticRow`: each numeric type once required and once nullable, and `Decimal` and `Int`
/// besides.
/// `Date` stands in for both of its timestamp types.
@Model(table: "nullable_arithmetic_rows")
class NullableArithmeticRowModel {
    @Key var id: Int64
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
    var requiredInt: Int
    var requiredDate: Date
    var nullableDate: Date?
    var requiredInterval: Interval
    var nullableInterval: Interval?
}

private typealias R = NullableArithmeticRowModel

// A nullable operand makes the result nullable. The annotations fail to compile when a result type changes.
private func arithmeticPropagatesNull() {
    let _: Expr<Int32> = R.requiredI32 + R.requiredI32

    let _: Expr<Int32?> = R.nullableI32 + 1
    let _: Expr<Int32?> = R.nullableI32 + R.requiredI32
    let _: Expr<Int32?> = R.requiredI32 + R.nullableI32
    let _: Expr<Int32?> = R.nullableI32 + R.nullableI32

    let _: Expr<Int32?> = R.nullableI32 - 1
    let _: Expr<Int32?> = R.nullableI32 - R.requiredI32
    let _: Expr<Int32?> = R.requiredI32 - R.nullableI32
    let _: Expr<Int32?> = R.nullableI32 - R.nullableI32

    let _: Expr<Int32?> = R.nullableI32 * 2
    let _: Expr<Int32?> = R.nullableI32 * R.requiredI32
    let _: Expr<Int32?> = R.requiredI32 * R.nullableI32
    let _: Expr<Int32?> = R.nullableI32 * R.nullableI32

    // Values on the left keep nullability too, including the non-commutative `-`.
    let _: Expr<Int32> = 1 - R.requiredI32
    let _: Expr<Int32?> = 1 + R.nullableI32
    let _: Expr<Int32?> = 1 - R.nullableI32
    let _: Expr<Int32?> = 2 * R.nullableI32

    // Two `smallint`s stay `smallint`, as in PostgreSQL; rust-dbkit types them `integer`.
    let _: Expr<Int16> = R.requiredI16 * R.requiredI16
    let _: Expr<Int16?> = R.nullableI16 + R.requiredI16
    let _: Expr<Int16?> = R.requiredI16 - R.nullableI16
    let _: Expr<Int16?> = R.nullableI16 * R.nullableI16

    // Every other numeric type keeps its own type.
    let _: Expr<Int64?> = R.nullableI64 + R.requiredI64
    let _: Expr<Float?> = R.requiredF32 - R.nullableF32
    let _: Expr<Double?> = R.nullableF64 * R.nullableF64
    let _: Expr<Decimal> = R.requiredDecimal * R.requiredDecimal
    let _: Expr<Decimal?> = R.nullableDecimal + R.requiredDecimal
    let _: Expr<Decimal?> = 100 - R.nullableDecimal

    // Nested expressions stay nullable on either side.
    let _: Expr<Int32?> = (R.nullableI32 + R.requiredI32) * (R.requiredI32 - R.requiredI32)
    let _: Expr<Int32?> = (R.requiredI32 + R.requiredI32) * (R.nullableI32 - R.requiredI32)
    let _: Expr<Int32?> = 100 - (R.nullableI32 + R.requiredI32)
}

// `+`, `-` and `*` follow PostgreSQL's promotion between numeric types, as `/` does below: the wider integer, and
// `double precision` once an integer meets a `real` or `double precision`, or a `real` meets a `double precision`.
// rust-dbkit accepts mixed types only in `/`.
private func mixedArithmeticPromotes() {
    let _: Expr<Int32> = R.requiredI16 + R.requiredI32
    let _: Expr<Int32?> = R.nullableI32 - R.requiredI16
    let _: Expr<Int64> = R.requiredI32 * R.requiredI64
    let _: Expr<Int64?> = R.requiredI16 + R.nullableI64
    let _: Expr<Int64> = R.requiredI64 - R.requiredI32
    let _: Expr<Double> = R.requiredI32 + R.requiredF64
    let _: Expr<Double> = R.requiredI16 - R.requiredF32
    let _: Expr<Double> = R.requiredI64 * R.requiredF32
    let _: Expr<Double?> = R.nullableF64 * R.requiredI16
    let _: Expr<Double> = R.requiredF32 - R.requiredF64
    let _: Expr<Double?> = R.nullableF32 + R.nullableF64
    let _: Expr<Float> = R.requiredF32 * R.requiredF32

    // An untyped literal takes the column's type; a typed value follows the promotion.
    let _: Expr<Int16> = R.requiredI16 + 1
    let _: Expr<Int16?> = 2 * R.nullableI16
    let _: Expr<Int64> = R.requiredI32 + Int64(1)
    let _: Expr<Double> = Float(2) * R.requiredI16
    let _: Expr<Double?> = R.nullableI64 - Double(1)

    // `Int` is `bigint`: it keeps its type with itself and promotes like `Int64` with the others.
    let _: Expr<Int> = R.requiredInt + R.requiredInt
    let _: Expr<Int> = R.requiredInt * 2
    let _: Expr<Int64> = R.requiredInt + R.requiredI32
    let _: Expr<Int64> = R.requiredI16 * R.requiredInt
    let _: Expr<Int64> = R.requiredInt - R.requiredI64
    let _: Expr<Int64> = R.requiredInt / R.requiredI32
    let _: Expr<Double> = R.requiredInt + R.requiredF32
}

// `/` follows PostgreSQL's promotion between the integer widths and `real` and `double precision`: the wider integer,
// `double precision` once an integer meets a `real` or either operand is `double precision`, and `real` only for
// `real` by `real`. Each pair is listed with required and nullable operands.
private func divisionPromotesAndPropagatesNull() {
    let _: Expr<Int16> = R.requiredI16 / R.requiredI16
    let _: Expr<Int16?> = R.nullableI16 / R.requiredI16
    let _: Expr<Int16?> = R.requiredI16 / R.nullableI16
    let _: Expr<Int16?> = R.nullableI16 / R.nullableI16
    let _: Expr<Int32> = R.requiredI16 / R.requiredI32
    let _: Expr<Int32?> = R.nullableI16 / R.requiredI32
    let _: Expr<Int32?> = R.requiredI16 / R.nullableI32
    let _: Expr<Int32?> = R.nullableI16 / R.nullableI32
    let _: Expr<Int64> = R.requiredI16 / R.requiredI64
    let _: Expr<Int64?> = R.nullableI16 / R.requiredI64
    let _: Expr<Int64?> = R.requiredI16 / R.nullableI64
    let _: Expr<Int64?> = R.nullableI16 / R.nullableI64
    let _: Expr<Double> = R.requiredI16 / R.requiredF32
    let _: Expr<Double?> = R.nullableI16 / R.requiredF32
    let _: Expr<Double?> = R.requiredI16 / R.nullableF32
    let _: Expr<Double?> = R.nullableI16 / R.nullableF32
    let _: Expr<Double> = R.requiredI16 / R.requiredF64
    let _: Expr<Double?> = R.nullableI16 / R.requiredF64
    let _: Expr<Double?> = R.requiredI16 / R.nullableF64
    let _: Expr<Double?> = R.nullableI16 / R.nullableF64

    let _: Expr<Int32> = R.requiredI32 / R.requiredI16
    let _: Expr<Int32?> = R.nullableI32 / R.requiredI16
    let _: Expr<Int32?> = R.requiredI32 / R.nullableI16
    let _: Expr<Int32?> = R.nullableI32 / R.nullableI16
    let _: Expr<Int32> = R.requiredI32 / R.requiredI32
    let _: Expr<Int32?> = R.nullableI32 / R.requiredI32
    let _: Expr<Int32?> = R.requiredI32 / R.nullableI32
    let _: Expr<Int32?> = R.nullableI32 / R.nullableI32
    let _: Expr<Int64> = R.requiredI32 / R.requiredI64
    let _: Expr<Int64?> = R.nullableI32 / R.requiredI64
    let _: Expr<Int64?> = R.requiredI32 / R.nullableI64
    let _: Expr<Int64?> = R.nullableI32 / R.nullableI64
    let _: Expr<Double> = R.requiredI32 / R.requiredF32
    let _: Expr<Double?> = R.nullableI32 / R.requiredF32
    let _: Expr<Double?> = R.requiredI32 / R.nullableF32
    let _: Expr<Double?> = R.nullableI32 / R.nullableF32
    let _: Expr<Double> = R.requiredI32 / R.requiredF64
    let _: Expr<Double?> = R.nullableI32 / R.requiredF64
    let _: Expr<Double?> = R.requiredI32 / R.nullableF64
    let _: Expr<Double?> = R.nullableI32 / R.nullableF64

    let _: Expr<Int64> = R.requiredI64 / R.requiredI16
    let _: Expr<Int64?> = R.nullableI64 / R.requiredI16
    let _: Expr<Int64?> = R.requiredI64 / R.nullableI16
    let _: Expr<Int64?> = R.nullableI64 / R.nullableI16
    let _: Expr<Int64> = R.requiredI64 / R.requiredI32
    let _: Expr<Int64?> = R.nullableI64 / R.requiredI32
    let _: Expr<Int64?> = R.requiredI64 / R.nullableI32
    let _: Expr<Int64?> = R.nullableI64 / R.nullableI32
    let _: Expr<Int64> = R.requiredI64 / R.requiredI64
    let _: Expr<Int64?> = R.nullableI64 / R.requiredI64
    let _: Expr<Int64?> = R.requiredI64 / R.nullableI64
    let _: Expr<Int64?> = R.nullableI64 / R.nullableI64
    let _: Expr<Double> = R.requiredI64 / R.requiredF32
    let _: Expr<Double?> = R.nullableI64 / R.requiredF32
    let _: Expr<Double?> = R.requiredI64 / R.nullableF32
    let _: Expr<Double?> = R.nullableI64 / R.nullableF32
    let _: Expr<Double> = R.requiredI64 / R.requiredF64
    let _: Expr<Double?> = R.nullableI64 / R.requiredF64
    let _: Expr<Double?> = R.requiredI64 / R.nullableF64
    let _: Expr<Double?> = R.nullableI64 / R.nullableF64

    let _: Expr<Double> = R.requiredF32 / R.requiredI16
    let _: Expr<Double?> = R.nullableF32 / R.requiredI16
    let _: Expr<Double?> = R.requiredF32 / R.nullableI16
    let _: Expr<Double?> = R.nullableF32 / R.nullableI16
    let _: Expr<Double> = R.requiredF32 / R.requiredI32
    let _: Expr<Double?> = R.nullableF32 / R.requiredI32
    let _: Expr<Double?> = R.requiredF32 / R.nullableI32
    let _: Expr<Double?> = R.nullableF32 / R.nullableI32
    let _: Expr<Double> = R.requiredF32 / R.requiredI64
    let _: Expr<Double?> = R.nullableF32 / R.requiredI64
    let _: Expr<Double?> = R.requiredF32 / R.nullableI64
    let _: Expr<Double?> = R.nullableF32 / R.nullableI64
    let _: Expr<Float> = R.requiredF32 / R.requiredF32
    let _: Expr<Float?> = R.nullableF32 / R.requiredF32
    let _: Expr<Float?> = R.requiredF32 / R.nullableF32
    let _: Expr<Float?> = R.nullableF32 / R.nullableF32
    let _: Expr<Double> = R.requiredF32 / R.requiredF64
    let _: Expr<Double?> = R.nullableF32 / R.requiredF64
    let _: Expr<Double?> = R.requiredF32 / R.nullableF64
    let _: Expr<Double?> = R.nullableF32 / R.nullableF64

    let _: Expr<Double> = R.requiredF64 / R.requiredI16
    let _: Expr<Double?> = R.nullableF64 / R.requiredI16
    let _: Expr<Double?> = R.requiredF64 / R.nullableI16
    let _: Expr<Double?> = R.nullableF64 / R.nullableI16
    let _: Expr<Double> = R.requiredF64 / R.requiredI32
    let _: Expr<Double?> = R.nullableF64 / R.requiredI32
    let _: Expr<Double?> = R.requiredF64 / R.nullableI32
    let _: Expr<Double?> = R.nullableF64 / R.nullableI32
    let _: Expr<Double> = R.requiredF64 / R.requiredI64
    let _: Expr<Double?> = R.nullableF64 / R.requiredI64
    let _: Expr<Double?> = R.requiredF64 / R.nullableI64
    let _: Expr<Double?> = R.nullableF64 / R.nullableI64
    let _: Expr<Double> = R.requiredF64 / R.requiredF32
    let _: Expr<Double?> = R.nullableF64 / R.requiredF32
    let _: Expr<Double?> = R.requiredF64 / R.nullableF32
    let _: Expr<Double?> = R.nullableF64 / R.nullableF32
    let _: Expr<Double> = R.requiredF64 / R.requiredF64
    let _: Expr<Double?> = R.nullableF64 / R.requiredF64
    let _: Expr<Double?> = R.requiredF64 / R.nullableF64
    let _: Expr<Double?> = R.nullableF64 / R.nullableF64

    let _: Expr<Decimal> = R.requiredDecimal / R.requiredDecimal
    let _: Expr<Decimal?> = R.nullableDecimal / R.requiredDecimal
    let _: Expr<Decimal?> = R.requiredDecimal / R.nullableDecimal
    let _: Expr<Decimal?> = R.nullableDecimal / R.nullableDecimal

    // Values on either side follow the same promotion.
    let _: Expr<Int32> = R.requiredI32 / Int16(2)
    let _: Expr<Double> = Double(1) / R.requiredI64
    let _: Expr<Double?> = Float(1) / R.nullableI32
    let _: Expr<Double> = SQL.power(2.0, 3) / R.requiredI64
    let _: Expr<Double?> = SQL.sum(R.requiredI32) / R.requiredF64
}

private func castsToDoubleKeepNullability() {
    let _: Expr<Double> = R.requiredI16.cast(to: Double.self)
    let _: Expr<Double?> = R.nullableI16.cast(to: Double.self)
    let _: Expr<Double> = R.requiredI32.cast(to: Double.self)
    let _: Expr<Double?> = R.nullableI32.cast(to: Double.self)
    let _: Expr<Double> = R.requiredI64.cast(to: Double.self)
    let _: Expr<Double?> = R.nullableI64.cast(to: Double.self)
    let _: Expr<Double> = R.requiredF32.cast(to: Double.self)
    let _: Expr<Double?> = R.nullableF32.cast(to: Double.self)
    let _: Expr<Double> = R.requiredF64.cast(to: Double.self)
    let _: Expr<Double?> = R.nullableF64.cast(to: Double.self)
    let _: Expr<Double> = (R.requiredI32 + R.requiredI32).cast(to: Double.self)
    let _: Expr<Double?> = SQL.sum(R.requiredI32).cast(to: Double.self)

    // Casting one integer operand divides with a fraction, leaving integer division as it is.
    let _: Expr<Double> = R.requiredI32.cast(to: Double.self) / R.requiredI64
    let _: Expr<Double?> = R.nullableI32.cast(to: Double.self) / R.requiredI64

    // `POWER` is `double precision` for any numbers but two `Decimal`s, which give `numeric`. A nullable operand makes
    // it nullable.
    let _: Expr<Double> = SQL.power(R.requiredF64, 2.0)
    let _: Expr<Double> = SQL.power(R.requiredI16, Int16(2))
    let _: Expr<Double> = SQL.power(R.requiredI32, R.requiredI64)
    let _: Expr<Double> = SQL.power(R.requiredF32, R.requiredI32)
    let _: Expr<Double> = SQL.power(R.requiredInt, 2)
    let _: Expr<Double?> = SQL.power(R.nullableI16, Int16(2))
    let _: Expr<Double?> = SQL.power(R.nullableI32, Int32(2))
    let _: Expr<Double?> = SQL.power(R.nullableI64, Int64(2))
    let _: Expr<Double?> = SQL.power(R.nullableF32, Float(2))
    let _: Expr<Double?> = SQL.power(R.nullableF64, 2.0)
    let _: Expr<Double?> = SQL.power(R.requiredI32, R.nullableI32)
    let _: Expr<Double?> = SQL.power(R.nullableI32, R.nullableI32)
    let _: Expr<Decimal> = SQL.power(R.requiredDecimal, R.requiredDecimal)
    let _: Expr<Decimal> = SQL.power(R.requiredDecimal, 2)
    let _: Expr<Decimal?> = SQL.power(R.nullableDecimal, R.requiredDecimal)
    let _: Expr<Decimal?> = SQL.power(R.requiredDecimal, R.nullableDecimal)

    // Interval constructors keep their input's nullability. Seconds take every integer width and fractions.
    let _: Expr<Interval> = SQL.interval(hours: R.requiredI32)
    let _: Expr<Interval?> = SQL.interval(days: R.nullableI32)
    let _: Expr<Interval?> = SQL.interval(hours: R.nullableI32)
    let _: Expr<Interval?> = SQL.interval(minutes: R.nullableI32)
    let _: Expr<Interval?> = SQL.interval(seconds: R.nullableI16)
    let _: Expr<Interval?> = SQL.interval(seconds: R.nullableI32)
    let _: Expr<Interval?> = SQL.interval(seconds: R.nullableI64)
    let _: Expr<Interval?> = SQL.interval(seconds: R.nullableF32)
    let _: Expr<Interval?> = SQL.interval(seconds: R.nullableF64)
}

private func comparisonsOnNullableArithmeticAreNullable() {
    let nullableSum = R.nullableI32 + R.requiredI32
    let _: Expr<Bool?> = nullableSum == 10
    let _: Expr<Bool?> = nullableSum == nil
    let _: Expr<Bool?> = nullableSum != 10
    let _: Expr<Bool?> = nullableSum < 10
    let _: Expr<Bool?> = nullableSum <= 10
    let _: Expr<Bool?> = nullableSum > 10
    let _: Expr<Bool?> = nullableSum >= 10
    let _: Expr<Bool?> = nullableSum.between(1, 10)

    let requiredRHS = R.requiredI32 + 1
    let _: Expr<Bool> = R.requiredI32 < requiredRHS
    let _: Expr<Bool> = R.requiredI32 <= requiredRHS
    let _: Expr<Bool> = R.requiredI32 > requiredRHS
    let _: Expr<Bool> = R.requiredI32 >= requiredRHS

    let nullableRHS = R.nullableI32 + 1
    let _: Expr<Bool?> = R.requiredI32 < nullableRHS
    let _: Expr<Bool?> = R.requiredI32 <= nullableRHS
    let _: Expr<Bool?> = R.requiredI32 > nullableRHS
    let _: Expr<Bool?> = R.requiredI32 >= nullableRHS
    let _: Expr<Bool?> = R.nullableI32 < requiredRHS
    let _: Expr<Bool?> = R.nullableI32 >= nullableRHS
    let _: Expr<Bool> = R.requiredI32 < (R.nullableI32 ?? 0)
    let _: Expr<Bool> = R.requiredI32 < SQL.coalesce(R.nullableI32, 0)

    // Timestamp arithmetic is NULL when the timestamp, the interval or both are.
    let _: Expr<Date?> = R.nullableDate + R.requiredInterval
    let _: Expr<Date?> = R.requiredDate + R.nullableInterval
    let _: Expr<Date?> = R.nullableDate + R.nullableInterval
    let _: Expr<Date?> = R.nullableDate - R.requiredInterval
    let _: Expr<Date?> = R.requiredDate - R.nullableInterval
    let _: Expr<Date?> = R.nullableDate - R.nullableInterval

    // A timestamp value on the left keeps the interval expression's NULL.
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let _: Expr<Date?> = timestamp + SQL.interval(hours: R.nullableI32)
    let _: Expr<Date?> = timestamp - SQL.interval(hours: R.nullableI32)

    // `DATE_TRUNC` keeps the timestamp's nullability, and `NOW()` is a required timestamp.
    let _: Expr<Date> = SQL.dateTrunc(.hour, R.requiredDate)
    let _: Expr<Date?> = SQL.dateTrunc(.hour, R.nullableDate)
    let _: Expr<Date?> = SQL.dateTrunc(.day, R.requiredDate + R.nullableInterval)
    let _: Expr<Date> = SQL.now()
    let _: Expr<Date> = SQL.dateTrunc(.day, SQL.now() - R.requiredInterval)

    _ = R.query()
        .filter(100 - R.nullableI32 > 50)
        .filter(R.nullableI32 + R.requiredI32 == 10)
        .filter(R.requiredI32 < R.nullableI32 + 1)
        .filter(R.requiredI32 >= R.nullableI32 + 1)
        .filter(R.nullableI32 * R.nullableI32 == nil)
        .filter((R.nullableDate + R.requiredInterval).isNotNull)
}
