import DBKit

// The string functions have descriptive names only, not PostgreSQL's.
private func postgreSQLNamesAreNotAliases() {
    _ = SQL.substr("abcdef", 2, 3)  // error: 'substr'
    _ = SQL.lpad("ab", 5, "x")  // error: 'lpad'
    _ = SQL.rpad("ab", 5, "x")  // error: 'rpad'
    _ = SQL.initcap("hello world")  // error: 'initcap'
    _ = SQL.overlay("abcdef", "X", 2, 3)  // error: 'overlay'
    _ = SQL.translate("abc", "a", "x")  // error: 'translate'
    _ = SQL.concatWS(",", "a", "b")  // error: 'concatWS'
    _ = SQL.stringToArray("a,b", ",")  // error: 'stringToArray'
}
