import DBKit

// Each tuple has one value per column of the row.

private func rowValueTuplesMatchTheRowArity() {
    let row = SQL.row(LookupItemModel.namespace, LookupItemModel.externalKey, LookupItemModel.locale)
    _ = LookupItemModel.query().filter(row.in([("public", "alpha"), ("internal", "beta")]))  // error: cannot convert
}
