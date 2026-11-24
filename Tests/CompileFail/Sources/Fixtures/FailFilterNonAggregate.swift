import DBKit

// Only an aggregate takes `filter`, and only once: PostgreSQL takes one `FILTER (WHERE …)` right after the aggregate
// call, so a wrapped or already filtered aggregate has no `filter`.
private func onlyAnAggregateTakesAFilter() {
    let positiveAmount = SaleModel.amount > 0
    let uppercased = SaleModel.region.uppercased()
    _ = uppercased.filter(positiveAmount)  // error: has no member 'filter'
    let coalesced = SQL.sum(SaleModel.amount) ?? 0
    _ = coalesced.filter(positiveAmount)  // error: has no member 'filter'
    _ = SQL.coalesce(SQL.sum(SaleModel.amount), 0).filter(positiveAmount)  // error: has no member 'filter'

    let filteredCount = SQL.count(SaleModel.id).filter(SaleModel.region == "us")
    _ = filteredCount.filter(positiveAmount)  // error: has no member 'filter'
}
