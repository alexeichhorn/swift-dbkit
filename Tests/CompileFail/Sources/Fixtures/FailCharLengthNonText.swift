import DBKit

/// rust-dbkit's `Flag` of `fail_char_length_non_text.rs`.
@Model(table: "flags")
class FlagModel {
    @Key var id: Int64
    var enabled: Bool
}

private func charLengthTakesText() {
    _ = SQL.charLength(FlagModel.enabled)  // error: 'charLength'
}
