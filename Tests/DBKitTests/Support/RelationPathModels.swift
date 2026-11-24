import DBKit

// rust-dbkit's `support/relation_paths.rs` and `support/relation_path_graphs.rs`, the models both relation-path test
// files share. The `Path` prefix keeps them apart from the kit's `MemberModel`, `OrganizationModel` and `RecordModel`.

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

/// Two foreign keys to one model, the second referencing a renamed unique column.
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

/// Creates the relation-path tables as temporary tables and seeds them. Missing targets are deliberate (owner 99,
/// organization 99, parent 99, a node that is its own parent): model annotations alone don't enforce foreign keys.
func setupRelationPaths(on tx: Transaction) async throws {
    try await tx.query("CREATE TEMP TABLE path_organizations (id BIGINT PRIMARY KEY, label TEXT NOT NULL)")
    try await tx.query(
        """
        CREATE TEMP TABLE path_members (
            id BIGINT PRIMARY KEY, organization_id BIGINT NOT NULL, label TEXT NOT NULL,
            enabled BOOLEAN NOT NULL, score INTEGER NOT NULL, note TEXT,
            external_ref TEXT NOT NULL UNIQUE)
        """)
    try await tx.query(
        "CREATE TEMP TABLE path_records (id BIGINT PRIMARY KEY, owner_id BIGINT, label TEXT NOT NULL, enabled BOOLEAN NOT NULL)")
    try await tx.query("CREATE TEMP TABLE path_assignments (id BIGINT PRIMARY KEY, first_id BIGINT, second_code TEXT)")
    try await tx.query("CREATE TEMP TABLE path_nodes (id BIGINT PRIMARY KEY, parent_id BIGINT, label TEXT NOT NULL)")
    try await tx.query("INSERT INTO path_organizations VALUES (1, 'north'), (2, 'south')")
    try await tx.query(
        """
        INSERT INTO path_members VALUES
            (1, 1, 'Atlas', true, 30, NULL, 'a'),
            (2, 2, 'Birch', false, 10, 'memo', 'b'),
            (3, 2, 'Cedar', true, 20, '', 'c'),
            (4, 99, 'Delta', false, 5, NULL, 'd')
        """)
    try await tx.query(
        """
        INSERT INTO path_records VALUES
            (1, 1, 'first', false), (2, 2, 'second', true), (3, 1, 'third', false),
            (4, 3, 'fourth', false), (5, NULL, 'fifth', true), (6, 99, 'sixth', false),
            (7, 4, 'seventh', false)
        """)
    try await tx.query(
        """
        INSERT INTO path_assignments VALUES
            (1, 1, 'b'), (2, 2, 'a'), (3, 1, 'a'), (4, NULL, 'a'),
            (5, 1, NULL), (6, 99, 'missing'), (7, 3, 'b'), (8, 2, 'b')
        """)
    try await tx.query(
        "INSERT INTO path_nodes VALUES (1, NULL, 'root'), (2, 1, 'branch'), (3, 2, 'leaf'), (4, 99, 'orphan'), (5, 5, 'cycle')")
}

/// `setupRelationPaths` plus a member without records and an organization without members, so an accidentally
/// uncorrelated `EXISTS` can't pass by returning every outer row.
func setupCorrelatedRelationPaths(on tx: Transaction) async throws {
    try await setupRelationPaths(on: tx)
    try await tx.query("INSERT INTO path_members VALUES (5, 1, 'atlas', false, 0, NULL, 'e')")
    try await tx.query("INSERT INTO path_organizations VALUES (3, 'unused')")
}
