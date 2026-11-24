import DBKit

/// rust-dbkit's `measurements` of `fail_bitwise_non_integer.rs`.
@Model(table: "measurements")
class MeasurementModel {
    @Key var id: Int64
    var label: String
    var ratio: Double
}

// Bitwise operators take integers only.
private func nonIntegersTakeNoBitwiseOperators() {
    _ = MeasurementModel.label & "mask"  // error: '&'
    _ = MeasurementModel.ratio | 1.0  // error: '|'
    _ = ~MeasurementModel.ratio  // error: '~'
}
