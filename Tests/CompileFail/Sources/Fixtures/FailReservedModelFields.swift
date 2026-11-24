import DBKit

@Model(table: "marker_fields")
class MarkerFieldModel {
    @Key var id: Int64
    var __dbkit_marker: String  // error: names starting with `__dbkit_` are reserved for DBKit internals
}

@Model(table: "future_fields")
class FutureFieldModel {
    @Key var id: Int64
    var __dbkit_future: Bool  // error: names starting with `__dbkit_` are reserved for DBKit internals
}

@Model(table: "renamed_fields")
class RenamedFieldModel {
    @Key var id: Int64
    @ColumnName("public_label") var __dbkit_label: String  // error: names starting with `__dbkit_` are reserved for DBKit internals
}

@Model(table: "raw_fields")
class RawFieldModel {
    @Key var id: Int64
    var `__dbkit_raw`: String  // error: names starting with `__dbkit_` are reserved for DBKit internals
}

@Model(table: "reserved_keys")
class ReservedKeyModel {
    @Key var __dbkit_id: Int64  // error: names starting with `__dbkit_` are reserved for DBKit internals
}

// Waits for slice 17: a reserved relation name, `@BelongsTo(key: "ownerID") var __dbkit_owner: TargetModel?`.
