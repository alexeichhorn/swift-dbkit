import DBKit

@Model(table: "accepted_fields")
class AcceptedModel {
    @Key var id: Int64
    var dbkit_value: Int32
    var _dbkit_value: Int32
    var __dbkit: Int32
    var __dbkitx_value: Int32
    // Only property names are reserved; existing database column names stay usable.
    @ColumnName("__dbkit_marker") var label: String
}

@Model(table: "sources")
class SourceModel {
    @Key var id: Int64
    var targetID: Int64
    @BelongsTo(key: "targetID") var target: AcceptedModel?
}

private func useAcceptedNames() {
    _ = AcceptedModel.query()
        .filter(AcceptedModel.dbkit_value == 1)
        .filter(AcceptedModel._dbkit_value == 2)
        .filter(AcceptedModel.__dbkit == 3)
        .filter(AcceptedModel.__dbkitx_value == 4)
        .filter(AcceptedModel.label == "value")
    _ = SourceModel.query()
        .filter(SourceModel.Relations.target.__dbkit == 3)
        .filter(SourceModel.Relations.target.label == "value")
}
