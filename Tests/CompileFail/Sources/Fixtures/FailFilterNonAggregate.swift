import DBKit

// Only an aggregate takes `filter`, and only once: PostgreSQL takes one `FILTER (WHERE …)` right after the aggregate
// call, so a wrapped or already filtered aggregate has no `filter`.
private func onlyAnAggregateTakesAFilter() {
    let positiveAmount = SaleModel.amount > 0
    // Waits for slice 15: `SaleModel.region.uppercased().filter(positiveAmount)` fails.
    let coalesced = SQL.sum(SaleModel.amount) ?? 0
    _ = coalesced.filter(positiveAmount)  // error: has no member 'filter'

    let filteredCount = SQL.count(SaleModel.id).filter(SaleModel.region == "us")
    _ = filteredCount.filter(positiveAmount)  // error: has no member 'filter'
}
