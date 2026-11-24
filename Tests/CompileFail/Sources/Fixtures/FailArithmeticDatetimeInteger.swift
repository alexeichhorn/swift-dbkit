import DBKit
import Foundation

/// rust-dbkit's `records` of `fail_arithmetic_datetime_integer.rs`.
@Model(table: "records")
class OccurrenceModel {
    @Key var id: Int64
    var occurredAt: Date
}

// A timestamp takes no integer in arithmetic.
private func timestampsTakeNoIntegers() {
    let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
    // Once `Date + Interval` exists, the error names the `Int64` operand rather than `+`.
    _ = OccurrenceModel.query().filter(OccurrenceModel.occurredAt + Int64(1) <= cutoff)  // error: Int64
    _ = OccurrenceModel.occurredAt / Int32(1)  // error: '/'
}
