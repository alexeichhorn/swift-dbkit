import Foundation

/// The date an ISO 8601 timestamp names, such as `2024-01-02T03:04:05Z` or `2024-03-14T10:15:00+05:00`.
func isoDate(_ timestamp: String) -> Date {
    try! Date(timestamp, strategy: .iso8601)
}
