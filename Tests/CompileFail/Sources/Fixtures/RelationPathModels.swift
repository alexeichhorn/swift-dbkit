import DBKit

// rust-dbkit's `support/relation_paths.rs` and `support/relation_path_graphs.rs` for the `*RelationPath*` fixtures, as
// `Tests/DBKitTests/Support/RelationPathModels.swift` declares them. This file has no marks, so it must compile.

@Model(table: "path_organizations")
class PathOrganizationModel {
    @Key var id: Int64
    var label: String
}

@Model(table: "path_members")
class PathMemberModel {
    @Key var id: Int64
    var organizationID: Int64
    var label: String
    var enabled: Bool
    var score: Int32
    var note: String?
    @Unique @ColumnName("external_ref") var code: String
    @BelongsTo(key: "organizationID") var organization: PathOrganizationModel?
}

@Model(table: "path_records")
class PathRecordModel {
    @Key var id: Int64
    var ownerID: Int64?
    var label: String
    var enabled: Bool
    @BelongsTo(key: "ownerID") var owner: PathMemberModel?
}

@Model(table: "path_assignments")
class PathAssignmentModel {
    @Key var id: Int64
    var firstID: Int64?
    var secondCode: String?
    @BelongsTo(key: "firstID") var first: PathMemberModel?
    @BelongsTo(key: "secondCode", references: "code") var second: PathMemberModel?
}

@Model(table: "path_nodes")
class PathNodeModel {
    @Key var id: Int64
    var parentID: Int64?
    var label: String
    @BelongsTo(key: "parentID") var parent: PathNodeModel?
}
