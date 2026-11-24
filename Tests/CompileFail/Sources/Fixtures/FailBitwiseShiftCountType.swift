import DBKit

/// rust-dbkit's `bit_registers` of `fail_bitwise_shift_count_type.rs`, with an `Int` count besides.
@Model(table: "shift_registers")
class ShiftRegisterModel {
    @Key var id: Int64
    var value: Int64
    var largeShift: Int64
    var plainShift: Int
}

// PostgreSQL does not implicitly narrow a `bigint` count to its `integer` shift count, and `Int` is `bigint`.
private func bigintShiftCountsAreRejected() {
    // Ordered by, so Swift cannot read the line as its own `Int64` shift of the instance property.
    _ = ShiftRegisterModel.query().orderBy((ShiftRegisterModel.value >> Int64(2)).asc)  // error: Int64
    // The same applies when the count comes from a column.
    _ = ShiftRegisterModel.value >> ShiftRegisterModel.largeShift  // error: '>>'
    _ = ShiftRegisterModel.value << ShiftRegisterModel.plainShift  // error: '<<'
}
