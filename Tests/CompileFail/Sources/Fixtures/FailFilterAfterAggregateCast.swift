import DBKit

// A cast wraps the aggregate, so the filter goes inside it: `SQL.sum(…).filter(…).cast(to:)`.
private func filterGoesBeforeTheCast() {
    let cast = SQL.sum(SaleModel.amount).cast(to: Double.self)
    _ = cast.filter(SaleModel.amount > 0)  // error: has no member 'filter'
}
