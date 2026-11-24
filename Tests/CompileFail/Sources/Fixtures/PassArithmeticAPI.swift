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
    let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
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
        .filter(ArithmeticRecordModel.occurredAt + SQL.interval(hours: 1) <= cutoff)
        .orderBy((ArithmeticRecordModel.baselineValue + ArithmeticRecordModel.leftValue).desc)
        .orderBy((ArithmeticRecordModel.leftUnits + ArithmeticRecordModel.rightUnits).desc)
        .orderBy((ArithmeticRecordModel.occurredAt - SQL.interval(hours: ArithmeticRecordModel.leftValue)).asc)
        .limit(25)
        .render()

    let projection: Projection<Int32, Int16> = ArithmeticRecordModel.query()
        .select(
            (ArithmeticRecordModel.baselineValue + ArithmeticRecordModel.leftValue).as("computed_value"),
            (ArithmeticRecordModel.leftUnits + ArithmeticRecordModel.rightUnits).as("total_units")
        )
    _ = projection.render()
}
