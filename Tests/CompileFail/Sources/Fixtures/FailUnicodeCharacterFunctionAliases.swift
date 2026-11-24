import DBKit

// The Unicode functions have descriptive names only, not PostgreSQL's.
private func unicodeNamesAreNotAliases() {
    _ = SQL.ascii("A")  // error: 'ascii'
    _ = SQL.chr(65)  // error: 'chr'
    _ = SQL.casefold("Straße")  // error: 'casefold'
    _ = SQL.unicodeAssigned("A")  // error: 'unicodeAssigned'
}
