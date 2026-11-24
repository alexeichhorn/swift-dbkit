import DBKit
import Foundation

/// rust-dbkit's `CastRow` of `fail_cast_invalid_types.rs`. Waits for slice 12: `var elapsed: Interval`.
@Model(table: "cast_rows")
class InvalidCastRowModel {
    @Key var id: Int64
    var enabled: Bool
    var recordedAt: Date
    var externalID: UUID
}

// Casts PostgreSQL has no cast for are rejected at compile time.
private func castsWithoutAPostgreSQLCast() {
    _ = InvalidCastRowModel.recordedAt.cast(to: Double.self)  // error: cast
    _ = InvalidCastRowModel.enabled.cast(to: Int64.self)  // error: cast
    _ = InvalidCastRowModel.externalID.cast(to: Date.self)  // error: cast
    // Waits for slice 12: `InvalidCastRowModel.elapsed.cast(to: Int32.self)` fails.
}
