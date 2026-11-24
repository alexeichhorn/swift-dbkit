import DBKit
import Foundation

/// rust-dbkit's `Metric` of `fail_sum_non_numeric.rs`.
@Model(table: "metrics")
class MetricModel {
    @Key var id: Int64
    var label: String
    var nullableLabel: String?
    var recordedAt: Date
}

// PostgreSQL sums numbers and intervals only.
private func sumTakesNumbersAndIntervalsOnly() {
    _ = SQL.sum(MetricModel.label)  // error: sum
    _ = SQL.sum(MetricModel.nullableLabel)  // error: sum
    _ = SQL.sum(MetricModel.recordedAt)  // error: sum
}
