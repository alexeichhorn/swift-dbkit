import DBKit
import Testing

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

    @Test func renamedColumnsAreUsedInMutationSQL() {
        let insert = RenamedParentModel.insert(RenamedParentModel.Insert(kind: "primary", externalReference: "ref-1", label: "Example"))
            .onConflict(RenamedParentModel.kind, doUpdate: RenamedParentModel.externalReference, RenamedParentModel.label)
            .returningAll()
            .render()
        #expect(
            insert.sql
                == #"INSERT INTO "renamed_parents" ("type", "external_ref", "label") VALUES ($1, $2, $3) ON CONFLICT ("type") DO UPDATE SET "external_ref" = EXCLUDED."external_ref", "label" = EXCLUDED."label" RETURNING *"#
        )
        #expect(insert.binds.map(\.description) == ["primary", "ref-1", "Example"])

        let update = RenamedParentModel.update()
            .set(RenamedParentModel.kind, to: "secondary")
            .set(RenamedParentModel.externalReference, to: "ref-2")
            .filter(RenamedParentModel.id == 1)
            .returningAll()
            .render()
        #expect(
            update.sql
                == #"UPDATE "renamed_parents" SET "type" = $1, "external_ref" = $2 WHERE "renamed_parents"."id" = $3 RETURNING *"#
        )
        #expect(update.binds.map(\.description) == ["secondary", "ref-2", "1"])
    }

    /// Joined columns are aliased by their database names, `type` and `sort_key`, not the property names.
    @Test func joinedLoadingSQLAliasesRenamedColumnsByDatabaseName() {
        let query: Query<RenamedParentModel.Loaded<[RenamedChildModel]>> = RenamedParentModel.query().with(\.children, .joined)
        #expect(
            query.render().sql
                == #"SELECT "renamed_parents".*, "renamed_children"."id" AS "children.id", "renamed_children"."parent_id" AS "children.parent_id", "renamed_children"."type" AS "children.type", "renamed_children"."sort_key" AS "children.sort_key" FROM "renamed_parents" LEFT JOIN "renamed_children" ON "renamed_children"."parent_id" = "renamed_parents"."id""#
        )
    }
}
