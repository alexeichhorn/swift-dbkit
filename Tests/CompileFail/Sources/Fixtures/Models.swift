import DBKit

// Models shared by the fixtures. This file has no marks, so it must compile.

@Model(table: "users")
class UserModel {
    @Key @AutoIncrement var id: Int64
    var name: String
    var email: String
}

/// rust-dbkit's `NullabilityRow` of the `*nullab*` fixtures: each value type once required and once nullable.
@Model(table: "nullability_rows")
class NullabilityRowModel {
    @Key var id: Int64
    var requiredText: String
    var nullableText: String?
    var requiredCount: Int32
    var nullableCount: Int32?
    var nullableLimit: Int32?
}

@Model(table: "run_payloads")
class RunPayloadModel {
    @Key var targetID: Int64
    @Key var runID: Int64
    var payload: String
    var source: String
    var version: Int64
}
