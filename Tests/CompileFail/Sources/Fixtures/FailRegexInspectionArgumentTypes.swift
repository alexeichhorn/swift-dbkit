import DBKit

// The text and the pattern are text.
private func regexInspectionTakesText() {
    _ = SQL.regexIsMatch(RegexSampleModel.number, "[0-9]")  // error: 'regexIsMatch'
    _ = SQL.regexCount(RegexSampleModel.source, RegexSampleModel.number)  // error: 'regexCount'
    _ = SQL.regexExtract(RegexSampleModel.number, RegexSampleModel.pattern)  // error: 'regexExtract'
}
