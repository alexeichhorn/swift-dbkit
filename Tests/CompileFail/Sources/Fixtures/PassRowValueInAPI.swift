import DBKit

// A row value's tuples take each column's type, `nil` included for a nullable column. Its `IN` is `Expr<Bool?>` when a
// column is nullable, even for an empty list, and `Expr<Bool>` otherwise.

private func rowValueInFollowsTheColumns() {
    let publicNamespace: String? = "public"
    let alpha: String? = "alpha"
    let internalNamespace: String? = "internal"

    let _: Expr<Bool> = SQL.row(LookupItemModel.namespace, LookupItemModel.externalKey).in([("public", "alpha")])
    let _: Expr<Bool?> = SQL.row(LookupItemModel.optionalNamespace, LookupItemModel.externalKey).in([("public", "alpha")])
    let _: Expr<Bool?> = SQL.row(LookupItemModel.namespace, LookupItemModel.optionalExternalKey).in([("public", "alpha")])
    let _: Expr<Bool?> = SQL.row(LookupItemModel.optionalNamespace, LookupItemModel.optionalExternalKey)
        .in([(publicNamespace, alpha), (internalNamespace, nil)])
    let _: Expr<Bool?> = SQL.row(LookupItemModel.namespace, LookupItemModel.optionalExternalKey, LookupItemModel.locale)
        .in([("public", "alpha", "en")])
    let _: Expr<Bool?> = SQL.row(LookupItemModel.namespace, LookupItemModel.externalKey, LookupItemModel.optionalLocale).in([])

    _ = LookupItemModel.query()
        .filter(SQL.row(LookupItemModel.namespace, LookupItemModel.externalKey).in([("public", "alpha"), ("internal", "beta")]))
        .filter(
            SQL.row(LookupItemModel.namespace, LookupItemModel.externalKey, LookupItemModel.locale)
                .in([("public", "alpha", "en"), ("internal", "beta", "de")])
        )
        .filter(SQL.row(LookupItemModel.namespace, LookupItemModel.optionalExternalKey).in([("public", alpha), ("internal", nil)]))
}
