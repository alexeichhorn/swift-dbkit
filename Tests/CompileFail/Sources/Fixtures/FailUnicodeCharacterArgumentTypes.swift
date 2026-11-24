import DBKit

// The text functions take text, the form is a `NormalizationForm` and a code point is an `Int32`.
private func unicodeFunctionsTakeTheirArgumentTypes() {
    _ = SQL.normalize(UnicodeSampleModel.codepoint, .nfc)  // error: 'normalize'
    _ = SQL.normalize(UnicodeSampleModel.text, "NFC")  // error: 'NormalizationForm'
    _ = SQL.firstCodepoint(UnicodeSampleModel.codepoint)  // error: 'firstCodepoint'
    _ = SQL.fromCodepoint(Int64(65))  // error: 'fromCodepoint'
    _ = SQL.isUnicodeAssigned(UnicodeSampleModel.codepoint)  // error: 'isUnicodeAssigned'
}
