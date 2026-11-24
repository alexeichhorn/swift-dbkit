import DBKit
import Foundation

@Model(table: "users")
class UserModel {
    @Key @AutoIncrement var id: Int64
    var name: String
    @Unique var email: String
    var region: String?
}

@Model(table: "todos")
class TodoModel {
    @Key @AutoIncrement var id: Int64
    @Index var userID: Int64
    var title: String
    var note: String?
    var isComplete: Bool = false
}

@Model(table: "order_lines")
class OrderLineModel {
    @Key var orderID: Int64
    @Key var lineID: Int64
    var note: String
}

@Model(table: "run_payloads")
class RunPayloadModel {
    @Key var targetID: Int64
    @Key var runID: Int64
    var payload: String
    var source: String
    var version: Int64
}

@Model(table: "nullable_rows")
class NullableRowModel {
    @Key @AutoIncrement var id: Int64
    var note: String?
}

/// A key with a nullable column.
@Model(table: "hints")
class HintModel {
    @Key var name: String
    @Key var region: String?
    var note: String
}

@Model(table: "sales")
class SaleModel {
    @Key @AutoIncrement var id: Int64
    var region: String
    var amount: Int64
    var createdAt: Date
}

/// The kit's `tasks`. Waits for slice 26: `var state: TaskState` and `var previousState: TaskState?`. Waits for slice
/// 28: `@DatabaseDefault var updatedAt: Date`.
@Model(table: "tasks")
class TaskModel {
    @Key @AutoIncrement var id: Int64
    var projectID: Int64
    var title: String
    var attempts: Int32 = 0
}

/// rust-dbkit's `records` of `arithmetic_support.rs` and `arithmetic_integration.rs`.
@Model(table: "records")
class RecordModel {
    @Key @AutoIncrement var id: Int64
    var leftValue: Int32
    var rightValue: Int32
    var realValue: Float
    var baselineValue: Int32
    var occurredAt: Date
}

/// rust-dbkit's `compact_records`: two `smallint` columns.
@Model(table: "compact_records")
class CompactRecordModel {
    @Key @AutoIncrement var id: Int64
    var leftUnits: Int16
    var rightUnits: Int16
}

struct Preferences: Codable, Hashable, DatabaseJSON {
    var theme: String
}

@Model(table: "documents")
class DocumentModel {
    @Key @AutoIncrement var id: Int64
    @ColumnName("type") var kind: String
    var tags: [String]
    var scores: [Int64]
    var preferences: Preferences?
    var payload: Data
    var accessMask: Int64
    var leaseWindow: Interval
}

/// rust-dbkit's `interval_rows` of `integration_interval.rs` and `type_support.rs`.
@Model(table: "interval_rows")
class IntervalRowModel {
    @Key var id: Int64
    var baseIntervalHours: Int32
    var backoffMinutes: Int32?
    var leaseWindow: Interval
}

/// rust-dbkit's `revision_snapshots` of `row_value_in_sql.rs` and `integration_row_value_in.rs`. `Date` stands in for
/// its `timestamp` column.
@Model(table: "revision_snapshots")
class RevisionSnapshotModel {
    @Key @AutoIncrement var id: Int64
    var seriesID: Int64
    var revision: Int32
    var capturedAt: Date
    var note: String
}

/// rust-dbkit's `events`. `Date` stands in for its `timestamp` and `date` columns; Swift has no type for its `time`
/// column `starts_at_time`.
@Model(table: "events")
class EventModel {
    @Key var id: UUID
    var name: String
    var startsAt: Date
    var day: Date
}

@Model(table: "events_tz")
class EventTzModel {
    @Key var id: UUID
    var title: String
    var startsAt: Date
    var endsAt: Date?
}

@Model(table: "profiles")
class ProfileModel {
    @Key @AutoIncrement var id: Int64
    var tags: [String]
}

/// rust-dbkit's `serde_json::Value` payload `{"name": …, "active": …}`, as a `Codable` type.
struct JSONPayload: Codable, Equatable, DatabaseJSON {
    var name: String
    var active: Bool
}

@Model(table: "json_rows")
class JSONRowModel {
    @Key @AutoIncrement var id: Int64
    var data: JSONPayload
}

@Model(table: "blob_rows")
class BlobRowModel {
    @Key @AutoIncrement var id: Int64
    var data: Data
    var dataOptional: Data?
}
