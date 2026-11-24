import DBKit

@Model(table: "renamed_parents")
class RenamedParentModel {
    @Key @AutoIncrement var id: Int64
    @ColumnName("type") var kind: String
    @ColumnName("external_ref") var externalReference: String
    var label: String
}

@Model(table: "renamed_children")
class RenamedChildModel {
    @Key @AutoIncrement var id: Int64
    var parentID: Int64
    @ColumnName("type") var kind: String
    @ColumnName("sort_key") var rankKey: Int64
}

private func useRenamedColumns() {
    _ = RenamedParentModel.kind
    _ = RenamedParentModel.externalReference
    _ = RenamedChildModel.kind
    _ = RenamedChildModel.rankKey

    _ = RenamedParentModel.query()
        .filter(RenamedParentModel.kind == "primary")
        .filter(RenamedParentModel.externalReference == "ref-1")
        .render()
    // Waits for slice 4: `RenamedParentModel.Insert` with the renamed columns and `update().set` on them.
    // Waits for slice 17: the `children`/`parent` relations and a loaded parent's `children`.
}
