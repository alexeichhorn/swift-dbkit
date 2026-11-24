import DBKit

// Interval units take numbers, not text.
private func intervalUnitsRejectText() {
    _ = SQL.interval(hours: "six")  // error: 'String'
}
