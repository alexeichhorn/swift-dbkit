import DBKit

// Each tuple value has its column's type: no other type, and no optional for a required column.

private func rowValueTuplesTakeTheColumnTypes() {
    let required = SQL.row(LookupItemModel.namespace, LookupItemModel.externalKey)
    let optional = SQL.row(LookupItemModel.optionalNamespace, LookupItemModel.externalKey)
    let publicNamespace: String? = "public"
    let one: Int64? = 1

    _ = LookupItemModel.query().filter(required.in([(Int64(1), "alpha"), (Int64(2), "beta")]))  // error: cannot convert
    _ = required.in([(publicNamespace, "alpha")])  // error: cannot convert
    _ = optional.in([(one, "alpha")])  // error: cannot convert
}
