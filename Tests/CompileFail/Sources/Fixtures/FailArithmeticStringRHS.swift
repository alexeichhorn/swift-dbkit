import DBKit

/// rust-dbkit's `records` of `fail_arithmetic_string_rhs.rs`.
@Model(table: "records")
class LabelRecordModel {
    @Key var id: Int64
    var label: String
}

// Text takes no number in arithmetic.
private func textTakesNoNumbers() {
    _ = LabelRecordModel.query().filter(LabelRecordModel.label + Int64(1) == "x")  // error: '+'
    _ = LabelRecordModel.label / Int64(1)  // error: '/'
}
