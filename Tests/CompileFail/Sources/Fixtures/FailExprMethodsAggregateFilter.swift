import DBKit

// `FILTER` attaches to the aggregate before `??` or a string method wraps it. rust-dbkit's `unwrap_or_default` line is
// the `??` line here.
private func wrappedAggregatesTakeNoFilter() {
    let positiveCount = MethodSampleModel.count > 0
    let total = SQL.sum(MethodSampleModel.count) ?? 0
    _ = total.filter(positiveCount)  // error: has no member 'filter'
    let trimmed = SQL.min(MethodSampleModel.text).trimmed()
    _ = trimmed.filter(positiveCount)  // error: has no member 'filter'
    let lowered = SQL.min(MethodSampleModel.text).lowercased()
    _ = lowered.filter(positiveCount)  // error: has no member 'filter'
    let matches = SQL.min(MethodSampleModel.text).hasPrefix("a")
    _ = matches.filter(positiveCount)  // error: has no member 'filter'
}
