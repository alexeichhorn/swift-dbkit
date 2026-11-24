import DBKit
import Testing

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

@Suite struct ColumnRenameSQLTests {
    @Test func renamedColumnMetadataUsesDatabaseName() {
        #expect(RenamedParentModel.kind.name == "type")
        #expect(RenamedParentModel.schema.columns[1] == "type")
        #expect(RenamedParentModel.externalReference.name == "external_ref")
        #expect(RenamedParentModel.schema.columns[2] == "external_ref")
        #expect(RenamedChildModel.kind.name == "type")
        #expect(RenamedChildModel.schema.columns[2] == "type")
        #expect(RenamedChildModel.rankKey.name == "sort_key")
        #expect(RenamedChildModel.schema.columns[3] == "sort_key")
    }

    @Test func renamedColumnsAreUsedInSelectSQL() {
        let rendered = RenamedParentModel.query()
            .filter(RenamedParentModel.kind == "primary")
            .filter(RenamedParentModel.externalReference == "ref-1")
            .orderBy(RenamedParentModel.externalReference.asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "renamed_parents".* FROM "renamed_parents" WHERE "renamed_parents"."type" = $1 AND "renamed_parents"."external_ref" = $2 ORDER BY "renamed_parents"."external_ref" ASC"#
        )
        #expect(rendered.binds.map(\.description) == ["primary", "ref-1"])
    }

    // Waits for slice 6: `renamedColumnsAreUsedInMutationSQL` (insert with `onConflict(_:doUpdate:)`, update).
    // Waits for slice 18: `joinedLoadingSQLAliasesRenamedColumnsByDatabaseName`, with `children`/`parent` relations on the models.
}
