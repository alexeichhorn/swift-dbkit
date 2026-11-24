import DBKit

@Model(table: "renamed_parents")
class RenamedParentModel {
    @Key @AutoIncrement var id: Int64
    @ColumnName("type") var kind: String
    @ColumnName("external_ref") var externalReference: String
    var label: String
    @HasMany var children: [RenamedChildModel]
}

@Model(table: "renamed_children")
class RenamedChildModel {
    @Key @AutoIncrement var id: Int64
    var parentID: Int64
    @ColumnName("type") var kind: String
    @ColumnName("sort_key") var rankKey: Int64
    @BelongsTo(key: "parentID") var parent: RenamedParentModel?
}

private func useRenamedColumns(loaded: RenamedParentModel.Loaded<[RenamedChildModel]>) {
    _ = RenamedParentModel.kind
    _ = RenamedParentModel.externalReference
    _ = RenamedChildModel.kind
    _ = RenamedChildModel.rankKey

    _ = RenamedParentModel.query()
        .filter(RenamedParentModel.kind == "primary")
        .filter(RenamedParentModel.externalReference == "ref-1")
        .render()
    _ = RenamedParentModel.insert(RenamedParentModel.Insert(kind: "primary", externalReference: "ref-1", label: "Example"))
    _ = RenamedParentModel.update()
        .set(RenamedParentModel.kind, to: "secondary")
        .set(RenamedParentModel.externalReference, to: "ref-2")
    let _: [RenamedChildModel] = loaded.children
}
