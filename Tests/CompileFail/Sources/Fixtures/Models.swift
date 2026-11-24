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

/// rust-dbkit's `LookupItem` of the `*row_value_in*` fixtures.
@Model(table: "lookup_items")
class LookupItemModel {
    @Key var id: Int64
    var namespace: String
    var optionalNamespace: String?
    var externalKey: String
    var optionalExternalKey: String?
    var locale: String
    var optionalLocale: String?
}

/// rust-dbkit's `MethodSample` of the `*expr_methods*` fixtures, without the columns only `unwrap_or_default` uses.
@Model(table: "method_samples")
class MethodSampleModel {
    @Key var id: Int64
    var text: String
    var optionalText: String?
    var prefix: String
    var optionalPrefix: String?
    var count: Int32
    var optionalCount: Int32?
    var optionalBool: Bool?
}

/// rust-dbkit's `Sale` of the `fail_filter_*` fixtures.
@Model(table: "sales")
class SaleModel {
    @Key var id: Int64
    var region: String
    var amount: Int64
}
