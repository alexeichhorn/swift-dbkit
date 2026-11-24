import DBKit
import Foundation

/// rust-dbkit's `records` of `pass_arithmetic_api.rs`.
@Model(table: "records")
class ArithmeticRecordModel {
    @Key var id: Int64
    var leftValue: Int32
    var rightValue: Int32
    var baselineValue: Int32
    var leftUnits: Int16
    var rightUnits: Int16
    var occurredAt: Date
}

private func arithmeticFiltersAndOrders() {
    // Two `smallint`s stay `smallint`, as in PostgreSQL; with an `integer` operand the result is `integer`.
    let _: Expr<Int16> = ArithmeticRecordModel.leftUnits + ArithmeticRecordModel.rightUnits
    let _: Expr<Int16> = ArithmeticRecordModel.leftUnits - ArithmeticRecordModel.rightUnits
    let _: Expr<Int32> = ArithmeticRecordModel.leftUnits + ArithmeticRecordModel.leftValue
    let _: Expr<Int32> = ArithmeticRecordModel.rightValue - ArithmeticRecordModel.rightUnits

    _ = ArithmeticRecordModel.query()
        .filter(ArithmeticRecordModel.leftValue + 1 < ArithmeticRecordModel.baselineValue)
        .filter(ArithmeticRecordModel.rightValue - ArithmeticRecordModel.leftValue >= 0)
        .filter(ArithmeticRecordModel.leftUnits + ArithmeticRecordModel.rightUnits > 3)
        .filter(ArithmeticRecordModel.leftUnits - ArithmeticRecordModel.rightUnits.cast(to: Int32.self) < Int32(5))
        .orderBy((ArithmeticRecordModel.baselineValue + ArithmeticRecordModel.leftValue).desc)
        .orderBy((ArithmeticRecordModel.leftUnits + ArithmeticRecordModel.rightUnits).desc)
        .limit(25)
        .render()
    // Waits for slice 12: the filter `occurredAt + 1 hour <= cutoff` and ordering by `occurredAt` minus `leftValue` hours.
    // Waits for slice 14: the projections `baselineValue + leftValue` and `leftUnits + rightUnits`.
}
