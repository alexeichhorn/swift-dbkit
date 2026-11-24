import DBKit
import Foundation

/// A `Decimal` column beside other numeric columns.
@Model(table: "decimal_rows")
class DecimalRowModel {
    @Key var id: Int64
    var price: Decimal
    var quantity: Int32
    var rate: Double
}

// `Decimal` combines only with `Decimal` in arithmetic, though PostgreSQL also accepts `numeric` with other numbers.
private func decimalTakesNoOtherNumbers() {
    _ = DecimalRowModel.price + DecimalRowModel.quantity  // error: Decimal
    _ = DecimalRowModel.rate * DecimalRowModel.price  // error: Decimal
    _ = DecimalRowModel.price / Int64(2)  // error: Decimal
}
