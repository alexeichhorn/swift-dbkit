import DBKit

// A target's columns named like the strategies of `with(_:)`, a Swift keyword-like name and a renamed column are all
// reachable as path columns.

@Model(table: "named_targets")
class NamedTargetModel {
    @Key var id: Int64
    var joined: Bool
    var selectIn: Bool
    var type: String
    @ColumnName("external_ref") var code: String
}

@Model(table: "named_sources")
class NamedSourceModel {
    @Key var id: Int64
    var targetID: Int64
    @BelongsTo(key: "targetID") var target: NamedTargetModel?
}

private func targetColumnsKeepTheirNames() {
    let target = NamedSourceModel.Relations.target
    let _: Expr<Bool?> = target.joined == true
    let _: Expr<Bool?> = target.selectIn == false
    let _: Expr<Bool?> = target.type == "primary"
    _ = NamedSourceModel.query().with(\.target, .joined).filter(target.joined == true)
    _ = NamedSourceModel.query().with(\.target, .selectIn).filter(target.selectIn == true)
    _ = NamedSourceModel.query().filter(target.code == "a")
}
