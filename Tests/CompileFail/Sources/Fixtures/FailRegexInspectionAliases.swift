import DBKit

// The regex inspection functions have descriptive names only, not PostgreSQL's.
private func regexInspectionNamesAreNotAliases() {
    _ = SQL.regexpIsMatch("abc", "a")  // error: 'regexpIsMatch'
    _ = SQL.regexpCount("abc", "a")  // error: 'regexpCount'
    _ = SQL.regexpPosition("abc", "a")  // error: 'regexpPosition'
    _ = SQL.regexpCaptures("abc", "a")  // error: 'regexpCaptures'
    _ = SQL.regexpExtract("abc", "a")  // error: 'regexpExtract'

    _ = SQL.regexpLike("abc", "a")  // error: 'regexpLike'
    _ = SQL.regexpInstr("abc", "a")  // error: 'regexpInstr'
    _ = SQL.regexpMatch("abc", "a")  // error: 'regexpMatch'
    _ = SQL.regexpSubstr("abc", "a")  // error: 'regexpSubstr'
}
