import DBKit

// `NullabilityRowModel.requiredText` and `requiredCount` are rust-dbkit's `label` and `attempts`. The text, pattern and
// replacement are text, and each function takes only its own flag type.
private func regexTransformsTakeTextAndTheirOwnFlags() {
    _ = SQL.regexReplace(NullabilityRowModel.requiredCount, "a", "x", [])  // error: 'regexReplace'
    _ = SQL.regexReplace(NullabilityRowModel.requiredText, NullabilityRowModel.requiredCount, "x", [])  // error: 'regexReplace'
    _ = SQL.regexReplace(NullabilityRowModel.requiredText, "a", NullabilityRowModel.requiredCount, [])  // error: 'regexReplace'
    _ = SQL.regexReplace(NullabilityRowModel.requiredText, "a", "x", "g")  // error: 'RegexReplaceFlags'
    _ = SQL.regexSplit(NullabilityRowModel.requiredText, "a", "i")  // error: 'RegexSplitFlags'
    _ = SQL.regexSplit(NullabilityRowModel.requiredText, "a", RegexReplaceFlags.global)  // error: 'RegexSplitFlags'
    _ = SQL.regexReplace(NullabilityRowModel.requiredText, "a", "x", RegexSplitFlags.caseInsensitive)  // error: 'RegexReplaceFlags'
}
