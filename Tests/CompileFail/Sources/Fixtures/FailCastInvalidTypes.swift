import DBKit
import Foundation

/// rust-dbkit's `CastRow` of `fail_cast_invalid_types.rs`.
@Model(table: "cast_rows")
class InvalidCastRowModel {
    @Key var id: Int64
    var enabled: Bool
    var recordedAt: Date
    var externalID: UUID
    var elapsed: Interval
}

// Casts PostgreSQL has no cast for are rejected at compile time.
private func castsWithoutAPostgreSQLCast() {
    _ = InvalidCastRowModel.recordedAt.cast(to: Double.self)  // error: cast
    _ = InvalidCastRowModel.enabled.cast(to: Int64.self)  // error: cast
    _ = InvalidCastRowModel.externalID.cast(to: Date.self)  // error: cast
    _ = InvalidCastRowModel.elapsed.cast(to: Int32.self)  // error: cast
}
