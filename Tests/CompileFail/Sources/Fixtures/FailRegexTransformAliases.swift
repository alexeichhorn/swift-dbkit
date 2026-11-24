import DBKit

// The regex transformation functions have descriptive names only, not PostgreSQL's.
private func regexTransformNamesAreNotAliases() {
    _ = SQL.regexpReplace("abc", "b", "x", [])  // error: 'regexpReplace'
    _ = SQL.regexpSplit("a,b", ",", [])  // error: 'regexpSplit'
    _ = SQL.regexpSplitToArray("a,b", ",", [])  // error: 'regexpSplitToArray'
    _ = SQL.regexSplitToArray("a,b", ",", [])  // error: 'regexSplitToArray'
}
