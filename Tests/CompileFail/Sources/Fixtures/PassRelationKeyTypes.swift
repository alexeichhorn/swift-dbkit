import DBKit

// Relations join on keys of each `RelationKey` type, and a nullable foreign key references a required key.

@Model(table: "small_parents")
class SmallParentModel {
    @Key var id: Int16
    @HasMany var children: [SmallChildModel]
}

@Model(table: "small_children")
class SmallChildModel {
    @Key var id: Int32
    var parentID: Int16?
    @BelongsTo(key: "parentID") var parent: SmallParentModel?
    @HasMany var grandchildren: [GrandchildModel]
}

@Model(table: "grandchildren")
class GrandchildModel {
    @Key var id: Int
    var parentID: Int32
    @BelongsTo(key: "parentID") var parent: SmallChildModel?
    @ManyToMany(through: GrandchildLinkModel.self, from: "grandchildID", to: "peerID") var peers: [GrandchildModel]
}

@Model(table: "grandchild_links")
class GrandchildLinkModel {
    @Key var grandchildID: Int
    @Key var peerID: Int
}

private func useRelationKeyTypes() {
    let _: Query<SmallParentModel.Loaded<[SmallChildModel.Loaded<NotLoaded, [GrandchildModel.Loaded<NotLoaded, [GrandchildModel]>]>]>> =
        SmallParentModel.query().with(\.children) { $0.with(\.grandchildren) { $0.with(\.peers) } }
}
