import DBKit

/// rust-dbkit's `bit_registers` of `pass_bitwise_api.rs` with an `Int` column besides, and without its `permissions`
/// columns of a custom integer-backed type.
@Model(table: "bit_registers")
class BitRegisterModel {
    @Key var id: Int64
    var smallValue: Int16
    var nullableSmall: Int16?
    var mediumValue: Int32
    var nullableMedium: Int32?
    var largeValue: Int64
    var nullableLarge: Int64?
    var plainValue: Int
    var smallShiftCount: Int16
    var nullableSmallShiftCount: Int16?
    var shiftCount: Int32
    var nullableShiftCount: Int32?
}

private typealias B = BitRegisterModel

// The annotations fail to compile when a result type changes.
private func bitwiseOperatorsFollowPostgres() {
    // Same-width binary operators keep the integer type.
    let _: Expr<Int16> = B.smallValue & Int16(1)
    let _: Expr<Int16> = B.smallValue | B.smallValue
    let _: Expr<Int16> = B.smallValue ^ Int16(1)
    let _: Expr<Int32> = B.mediumValue & Int32(1)
    let _: Expr<Int32> = B.mediumValue | B.mediumValue
    let _: Expr<Int32> = B.mediumValue ^ Int32(1)
    let _: Expr<Int64> = B.largeValue & Int64(1)
    let _: Expr<Int64> = B.largeValue | B.largeValue
    let _: Expr<Int64> = B.largeValue ^ Int64(1)

    // Mixed widths give the wider type.
    let _: Expr<Int32> = B.smallValue & B.mediumValue
    let _: Expr<Int32> = B.mediumValue | B.smallValue
    let _: Expr<Int64> = B.smallValue ^ B.largeValue
    let _: Expr<Int64> = B.largeValue & B.mediumValue
    let _: Expr<Int32> = B.smallValue | Int32(1)
    let _: Expr<Int64> = B.mediumValue ^ Int64(1)

    // Values work on the left too.
    let _: Expr<Int16> = Int16(1) & B.smallValue
    let _: Expr<Int32> = Int16(1) | B.mediumValue
    let _: Expr<Int64> = Int32(1) ^ B.largeValue
    let _: Expr<Int64> = Int64(1) & B.smallValue

    // An untyped literal takes the other operand's type on either side; a shift count literal is `Int32`.
    let _: Expr<Int16> = B.smallValue & 1
    let _: Expr<Int16> = 1 | B.smallValue
    let _: Expr<Int64?> = 1 & B.nullableLarge
    let _: Expr<Int16> = B.smallValue << 1

    // `Int` is `bigint`: with `Int` it stays `Int`, with another integer type it is `Int64`.
    let _: Expr<Int> = B.plainValue & B.plainValue
    let _: Expr<Int> = B.plainValue | 1
    let _: Expr<Int64> = B.plainValue ^ B.largeValue
    let _: Expr<Int64> = B.mediumValue & B.plainValue
    let _: Expr<Int> = ~B.plainValue
    let _: Expr<Int> = B.plainValue << B.shiftCount

    // `~` and shifts keep the left operand's type. `Int16` shift counts widen to `Int32`.
    let _: Expr<Int16> = ~B.smallValue
    let _: Expr<Int32> = ~B.mediumValue
    let _: Expr<Int64> = ~B.largeValue
    let _: Expr<Int16> = B.smallValue << Int32(1)
    let _: Expr<Int64> = B.largeValue << Int16(1)
    let _: Expr<Int64> = B.largeValue >> B.smallShiftCount
    let _: Expr<Int32> = B.mediumValue >> B.shiftCount
    let _: Expr<Int64> = B.largeValue << B.shiftCount
    let _: Expr<Int64> = Int64(1) << B.shiftCount
    let _: Expr<Int32> = Int32(16) >> B.shiftCount

    // A nullable operand makes the result nullable.
    let _: Expr<Int16?> = B.nullableSmall & B.smallValue
    let _: Expr<Int16?> = B.smallValue | B.nullableSmall
    let _: Expr<Int32?> = B.nullableSmall ^ B.mediumValue
    let _: Expr<Int32?> = B.smallValue & B.nullableMedium
    let _: Expr<Int64?> = B.nullableMedium | B.largeValue
    let _: Expr<Int64?> = B.largeValue ^ B.nullableMedium
    let _: Expr<Int64?> = B.nullableLarge & Int64(1)
    let _: Expr<Int64?> = B.nullableLarge | B.nullableLarge
    let _: Expr<Int64?> = ~B.nullableLarge
    let _: Expr<Int64?> = B.nullableLarge << B.shiftCount
    let _: Expr<Int64?> = B.largeValue >> B.nullableSmallShiftCount
    let _: Expr<Int64?> = B.largeValue >> B.nullableShiftCount
    let _: Expr<Int64?> = B.nullableLarge << B.nullableShiftCount
    let _: Expr<Int64?> = Int64(1) << B.nullableShiftCount
    let _: Expr<Int64> = Int64(1) << B.smallShiftCount

    // Expressions nest and compare like any other typed expression.
    let folded = ~(((B.largeValue & 255) ^ (B.largeValue >> 4)) | 1)
    let _: Expr<Int64> = folded
    let _: Expr<Bool> = folded != 0

    let nullableFolded = (B.nullableLarge & 255) ^ (B.largeValue >> 4)
    let _: Expr<Int64?> = nullableFolded
    let _: Expr<Bool?> = nullableFolded != 0

    _ = B.query()
        .filter((B.nullableLarge & 1) == 1)
        .orderBy((B.largeValue ^ 255).desc)
        .render()
    // Waits for slice 14: the projections `mediumValue | 8` as `enabled_value` and `largeValue << shiftCount` as
    // `shifted_value`.

    _ = B.update()
        .set(B.mediumValue, to: B.smallValue & B.mediumValue)
        .set(B.nullableLarge, to: B.largeValue << B.smallShiftCount)
        .filter(B.id == 1)
        .render()
}
