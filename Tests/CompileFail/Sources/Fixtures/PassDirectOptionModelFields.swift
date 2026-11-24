import DBKit

// `@Model` reads nullability from the resolved type, however the property spells it.

typealias RequiredText = String

@Model(table: "direct_option_rows")
class DirectOptionRowModel {
    @Key var id: Int64
    var requiredText: RequiredText
    var nullableText: Optional<String>
    var qualifiedNullableCount: Swift.Optional<Int32>
}

private func useDirectOptionFields() {
    let _: Column<DirectOptionRowModel, String> = DirectOptionRowModel.requiredText
    let _: Column<DirectOptionRowModel, String?> = DirectOptionRowModel.nullableText
    let _: Column<DirectOptionRowModel, Int32?> = DirectOptionRowModel.qualifiedNullableCount

    _ = DirectOptionRowModel.insert(
        DirectOptionRowModel.Insert(id: 1, requiredText: "required", nullableText: nil, qualifiedNullableCount: 2))
}
