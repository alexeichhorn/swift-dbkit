import DBKit

// The character set to trim is text.
private func trimCharacterSetsAreText() {
    _ = SQL.trimChars(TextSampleModel.title, Int32(1))  // error: 'trimChars'
    _ = SQL.trimStartChars(TextSampleModel.title, Int32(1))  // error: 'trimStartChars'
    _ = SQL.trimEndChars(TextSampleModel.title, Int32(1))  // error: 'trimEndChars'
}
