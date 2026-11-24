import DBKit
import Testing

/// rust-dbkit's `relation_paths_sql.rs`, which finds each join's alias in the SQL and checks how it is used; these
/// compare the whole SQL. A path's join is named by its table, or by the query's table and the relation names
/// (`"path_assignments.second"`) when the table's name is taken. Rust's tests that execute against a capturing
/// executor check the SQL `render()` returns.
@Suite struct RelationPathsSQLTests {
    @Test func filterAddsALeftJoinWithoutSelectingOrLoadingTheRelation() {
        let enabled: Expr<Bool?> = PathRecordModel.Relations.owner.enabled == true
        let query: Query<PathRecordModel> = PathRecordModel.query().filter(enabled)
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."enabled" = $1"#
        )
        #expect(rendered.binds.map(\.description) == ["true"])
    }

    @Test func scalarLeftArithmeticKeepsOperandOrderBindsAndNestedRelationPaths() {
        let owner = PathRecordModel.Relations.owner
        let remaining: Expr<Int32?> = Int32(100) - owner.score
        let rendered = PathRecordModel.query()
            .select(
                Int32(1) + owner.score,
                Int32(100) - owner.score,
                Int32(2) * owner.score,
                Double(60) / owner.score,
                Int64(10) - owner.organization.id
            )
            .filter(remaining > Int32(70))
            .orderBy(remaining.asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT ($1 + "path_members"."score"), ($2 - "path_members"."score"), ($3 * "path_members"."score"), ($4 / "path_members"."score"), ($5 - "path_organizations"."id") FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" LEFT JOIN "path_organizations" ON "path_organizations"."id" = "path_members"."organization_id" WHERE ($6 - "path_members"."score") > $7 ORDER BY ($8 - "path_members"."score") ASC"#
        )
        // Every use of a value binds it again; see "Repeated values" in docs/rust-parity.md.
        #expect(
            typedBinds(rendered) == [
                "Int32(1)", "Int32(100)", "Int32(2)", "Double(60.0)", "Int64(10)", "Int32(100)", "Int32(70)", "Int32(100)",
            ])
    }

    @Test func scalarLeftBitwiseAndShiftOperatorsShareTheRelationJoin() {
        let owner = PathRecordModel.Relations.owner
        let rendered = PathRecordModel.query()
            .select(
                Int32(7) & owner.score,
                Int32(8) | owner.score,
                Int32(3) ^ owner.score,
                Int64(1) << owner.score,
                Int64(1024) >> owner.score
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT ($1 & "path_members"."score"), ($2 | "path_members"."score"), ($3 # "path_members"."score"), ($4 << "path_members"."score"), ($5 >> "path_members"."score") FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id""#
        )
        #expect(typedBinds(rendered) == ["Int32(7)", "Int32(8)", "Int32(3)", "Int64(1)", "Int64(1024)"])
    }

    @Test func repeatedColumnsAndComputedExpressionsReuseThePath() {
        let owner = PathRecordModel.Relations.owner
        let rendered = PathRecordModel.query()
            .filter(owner.enabled == true)
            .filter(SQL.lower(owner.label) == "atlas")
            .filter(owner.score + 1 > 10)
            .orderBy(owner.score.desc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."enabled" = $1 AND LOWER("path_members"."label") = $2 AND ("path_members"."score" + $3) > $4 ORDER BY "path_members"."score" DESC"#
        )
        #expect(rendered.binds.map(\.description) == ["true", "atlas", "1", "10"])
    }

    @Test func orAndNullChecksKeepTheAutomaticJoinOuter() {
        let missingOwner: Expr<Bool> = PathRecordModel.Relations.owner.id.isNull
        let rendered = PathRecordModel.query().filter(PathRecordModel.enabled == true || missingOwner).render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE ("path_records"."enabled" = $1 OR "path_members"."id" IS NULL)"#
        )
    }

    @Test func renamedColumnsUseDatabaseNamesAndValuesStayBound() {
        let value = "x' OR true --"
        let rendered = PathRecordModel.query().filter(PathRecordModel.Relations.owner.code == value).render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."external_ref" = $1"#
        )
        #expect(!rendered.sql.contains(value))
        #expect(rendered.binds.map(\.description) == [value])
    }

    @Test func orderOnlyPathsAddJoinsBeforePagination() {
        let rendered = PathRecordModel.query()
            .orderBy(PathRecordModel.Relations.owner.label.asc)
            .orderBy(PathRecordModel.id.asc)
            .limit(2)
            .offset(1)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" ORDER BY "path_members"."label" ASC, "path_records"."id" ASC LIMIT 2 OFFSET 1"#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func automaticLeftJoinForUpdateScopesLockToBaseTable() {
        // Ordering preserves the outer join; a filter could let PostgreSQL simplify it to an inner join.
        let rendered = PathRecordModel.query().orderBy(PathRecordModel.Relations.owner.id.asc).forUpdate().render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" ORDER BY "path_members"."id" ASC FOR UPDATE OF "path_records""#
        )
    }

    @Test func projectionOnlyPathsAddJoinsAndKeepOutputAliases() {
        let owner = PathRecordModel.Relations.owner
        let note: Expr<String> = SQL.coalesce(owner.note, "missing")
        // A projection names all of its expressions or none, so the record's id is named too.
        let query: Projection<Int64, String?, String> = PathRecordModel.query()
            .select(PathRecordModel.id.as("id"), owner.label.as("owner_label"), note.as("note"))
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT "path_records"."id" AS "id", "path_members"."label" AS "owner_label", COALESCE("path_members"."note", $1) AS "note" FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id""#
        )
        #expect(rendered.binds.map(\.description) == ["missing"])
    }

    @Test func groupByAndHavingAlsoDiscoverRelationPaths() {
        let owner = PathRecordModel.Relations.owner
        let grouped = PathRecordModel.query().select(SQL.count(PathRecordModel.id)).groupBy(owner.enabled).render()
        #expect(
            grouped.sql
                == #"SELECT COUNT("path_records"."id") FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" GROUP BY "path_members"."enabled""#
        )

        let having = PathRecordModel.query().select(SQL.count(PathRecordModel.id)).having(SQL.count(owner.id) > 0).render()
        #expect(
            having.sql
                == #"SELECT COUNT("path_records"."id") FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" HAVING COUNT("path_members"."id") > $1"#
        )
        #expect(having.binds.map(\.description) == ["0"])
    }

    @Test func explicitJoinKindIsPreservedWithoutAnExtraImplicitJoin() {
        let enabled = PathRecordModel.Relations.owner.enabled == true
        let inner = PathRecordModel.query().join(\.owner).filter(enabled).render()
        #expect(
            inner.sql
                == #"SELECT "path_records".* FROM "path_records" JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."enabled" = $1"#
        )

        let outer = PathRecordModel.query().filter(enabled).leftJoin(\.owner).render()
        #expect(
            outer.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."enabled" = $1"#
        )
    }

    @Test func customTableJoinKeepsItsColumnsWhenARelationPathUsesTheSameTable() {
        // A custom ON condition is not interchangeable with the declared relation.
        let rendered = PathRecordModel.query()
            .leftJoin(PathMemberModel.self, on: PathMemberModel.id == PathRecordModel.ownerID && PathMemberModel.score > 25)
            .filter(PathMemberModel.note.isNull)
            .filter(PathRecordModel.Relations.owner.code == "c")
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON ("path_members"."id" = "path_records"."owner_id" AND "path_members"."score" > $1) LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" WHERE "path_members"."note" IS NULL AND "path_records.owner"."external_ref" = $2"#
        )
        #expect(rendered.binds.map(\.description) == ["25", "c"])
    }

    @Test func filterRelationJoinPrecedesACustomJoinThatUsesItsAlias() {
        let on = PathOrganizationModel.id == PathMemberModel.organizationID && PathOrganizationModel.label == "north"
        let enabled = PathRecordModel.Relations.owner.enabled == true
        for query in [
            PathRecordModel.query().join(PathOrganizationModel.self, on: on).filter(enabled),
            PathRecordModel.query().filter(enabled).join(PathOrganizationModel.self, on: on),
        ] {
            let rendered = query.render()
            // `PathMemberModel.organizationID` in ON is the owner join, which must already be in scope.
            #expect(
                rendered.sql
                    == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" JOIN "path_organizations" ON ("path_organizations"."id" = "path_members"."organization_id" AND "path_organizations"."label" = $1) WHERE "path_members"."enabled" = $2"#
            )
            #expect(rendered.binds.map(\.description) == ["north", "true"])
        }
    }

    @Test func projectionRelationJoinPrecedesACustomLeftJoinThatUsesItsAlias() {
        let query: Projection<Int64, String?, String> = PathRecordModel.query()
            .leftJoin(PathOrganizationModel.self, on: PathOrganizationModel.id == PathMemberModel.organizationID)
            .select(PathRecordModel.id, PathRecordModel.Relations.owner.label, PathOrganizationModel.label)
        let rendered = query.render()
        #expect(
            rendered.sql
                == #"SELECT "path_records"."id", "path_members"."label", "path_organizations"."label" FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" LEFT JOIN "path_organizations" ON "path_organizations"."id" = "path_members"."organization_id""#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func relationJoinPrecedesACorrelatedExistsInACustomJoinCondition() {
        let on =
            PathOrganizationModel.id == 1
            && SQL.exists(
                PathAssignmentModel.query()
                    .filter(PathAssignmentModel.firstID == PathMemberModel.id)
                    .filter(PathAssignmentModel.secondCode == "b")
            )
        let enabled = PathRecordModel.Relations.owner.enabled == true
        for query in [
            PathRecordModel.query().join(PathOrganizationModel.self, on: on).filter(enabled),
            PathRecordModel.query().filter(enabled).join(PathOrganizationModel.self, on: on),
        ] {
            let rendered = query.render()
            #expect(
                rendered.sql
                    == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" JOIN "path_organizations" ON ("path_organizations"."id" = $1 AND EXISTS (SELECT "path_assignments".* FROM "path_assignments" WHERE "path_assignments"."first_id" = "path_members"."id" AND "path_assignments"."second_code" = $2)) WHERE "path_members"."enabled" = $3"#
            )
            #expect(rendered.binds.map(\.description) == ["1", "b", "true"])
        }
    }

    @Test func relationJoinPrecedesACorrelationThroughNestedJoinSubqueries() {
        let rendered = PathRecordModel.query()
            .leftJoin(
                PathOrganizationModel.self,
                on: SQL.exists(
                    PathAssignmentModel.query().whereExists(PathNodeModel.query().filter(PathNodeModel.id == PathMemberModel.id))
                )
            )
            .select(PathRecordModel.id, PathRecordModel.Relations.owner.score)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records"."id", "path_members"."score" FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" LEFT JOIN "path_organizations" ON EXISTS (SELECT "path_assignments".* FROM "path_assignments" WHERE EXISTS (SELECT "path_nodes".* FROM "path_nodes" WHERE "path_nodes"."id" = "path_members"."id"))"#
        )
    }

    @Test func uncorrelatedJoinSubqueryKeepsItsRelationPathsLocal() {
        let rendered = PathRecordModel.query()
            .join(
                PathOrganizationModel.self,
                on: SQL.exists(PathMemberModel.query().filter(PathMemberModel.Relations.organization.label == "north"))
            )
            .select(PathRecordModel.id, PathRecordModel.Relations.owner.score)
            .render()
        // The member belongs to the subquery here, so its organization path stays there, under a name the enclosing
        // query doesn't use. Nothing in ON needs the owner join, so the custom join keeps its place.
        #expect(
            rendered.sql
                == #"SELECT "path_records"."id", "path_members"."score" FROM "path_records" JOIN "path_organizations" ON EXISTS (SELECT "path_members".* FROM "path_members" LEFT JOIN "path_organizations" AS "path_members.organization" ON "path_members.organization"."id" = "path_members"."organization_id" WHERE "path_members.organization"."label" = $1) LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id""#
        )
        #expect(rendered.binds.map(\.description) == ["north"])
    }

    @Test func nestedJoinDependenciesMoveTogetherWithoutReorderingCustomJoins() {
        let rendered = PathRecordModel.query()
            .join(PathNodeModel.self, on: PathNodeModel.id == PathRecordModel.id)
            .join(PathAssignmentModel.self, on: PathAssignmentModel.firstID == PathOrganizationModel.id)
            .filter(PathRecordModel.Relations.owner.organization.label == "north")
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" JOIN "path_nodes" ON "path_nodes"."id" = "path_records"."id" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" LEFT JOIN "path_organizations" ON "path_organizations"."id" = "path_members"."organization_id" JOIN "path_assignments" ON "path_assignments"."first_id" = "path_organizations"."id" WHERE "path_organizations"."label" = $1"#
        )
    }

    // Rust's three "dynamic" tests build the path column a second way, from a column and relation descriptors, and
    // compare it with `Record::owner.<column>`. A Swift path column has only the `Relations` spelling, so these check
    // that spelling inside a custom join's condition.

    @Test func dynamicRelationColumnKeepsCustomJoinPredicatesAndBinds() {
        let enabled = PathRecordModel.Relations.owner.enabled == true
        let inner = PathRecordModel.query().join(PathMemberModel.self, on: enabled).render()
        #expect(
            inner.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" JOIN "path_members" ON "path_records.owner"."enabled" = $1"#
        )
        #expect(inner.binds.map(\.description) == ["true"])

        let outer = PathRecordModel.query().leftJoin(PathMemberModel.self, on: enabled).render()
        #expect(
            outer.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" LEFT JOIN "path_members" ON "path_records.owner"."enabled" = $1"#
        )
        #expect(outer.binds.map(\.description) == ["true"])
    }

    @Test func dynamicRelationKeyComparedToALiteralIsACustomJoin() {
        // Even the relation's target key is not a foreign-key join when the other side is a value.
        let rendered = PathRecordModel.query().join(PathMemberModel.self, on: PathRecordModel.Relations.owner.id == 1).render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" JOIN "path_members" ON "path_records.owner"."id" = $1"#
        )
        #expect(rendered.binds.map(\.description) == ["1"])
    }

    @Test func dynamicRelationKeyComparedToAnotherSourceColumnKeepsThatColumn() {
        // The caller chose the record's id, not its owner_id foreign key.
        let rendered = PathRecordModel.query()
            .join(PathMemberModel.self, on: PathRecordModel.Relations.owner.id == PathRecordModel.id)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" JOIN "path_members" ON "path_records.owner"."id" = "path_records"."id""#
        )
        #expect(rendered.binds.isEmpty)
    }

    @Test func nestedPathsShareTheirPrefixAndJoinInDependencyOrder() {
        let owner = PathRecordModel.Relations.owner
        let rendered = PathRecordModel.query()
            .filter(owner.organization.label == "north")
            .filter(owner.enabled == true)
            .orderBy(owner.organization.id.asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" LEFT JOIN "path_organizations" ON "path_organizations"."id" = "path_members"."organization_id" WHERE "path_organizations"."label" = $1 AND "path_members"."enabled" = $2 ORDER BY "path_organizations"."id" ASC"#
        )
        #expect(rendered.binds.map(\.description) == ["north", "true"])
    }

    @Test func siblingPathsKeepDistinctAliasesAndTheirOwnReferenceKeys() {
        let first = PathAssignmentModel.Relations.first
        let second = PathAssignmentModel.Relations.second
        let rendered = PathAssignmentModel.query()
            .filter(first.enabled == true)
            .filter(second.enabled == false)
            .filter(first.score > second.score)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_assignments".* FROM "path_assignments" LEFT JOIN "path_members" ON "path_members"."id" = "path_assignments"."first_id" LEFT JOIN "path_members" AS "path_assignments.second" ON "path_assignments.second"."external_ref" = "path_assignments"."second_code" WHERE "path_members"."enabled" = $1 AND "path_assignments.second"."enabled" = $2 AND "path_members"."score" > "path_assignments.second"."score""#
        )
        #expect(rendered.binds.map(\.description) == ["true", "false"])
    }

    @Test func nestedSiblingPathsDoNotMergeAtTheSameTargetTable() {
        let rendered = PathAssignmentModel.query()
            .filter(PathAssignmentModel.Relations.first.organization.label == "north")
            .filter(PathAssignmentModel.Relations.second.organization.label == "south")
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_assignments".* FROM "path_assignments" LEFT JOIN "path_members" ON "path_members"."id" = "path_assignments"."first_id" LEFT JOIN "path_organizations" ON "path_organizations"."id" = "path_members"."organization_id" LEFT JOIN "path_members" AS "path_assignments.second" ON "path_assignments.second"."external_ref" = "path_assignments"."second_code" LEFT JOIN "path_organizations" AS "path_assignments.second.organization" ON "path_assignments.second.organization"."id" = "path_assignments.second"."organization_id" WHERE "path_organizations"."label" = $1 AND "path_assignments.second.organization"."label" = $2"#
        )
    }

    @Test func selfPathsKeepTheBaseParentAndGrandparentDistinct() {
        let rendered = PathNodeModel.query()
            .filter(PathNodeModel.label == "leaf")
            .filter(PathNodeModel.Relations.parent.label == "branch")
            .filter(PathNodeModel.Relations.parent.parent.label == "root")
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_nodes".* FROM "path_nodes" LEFT JOIN "path_nodes" AS "path_nodes.parent" ON "path_nodes.parent"."id" = "path_nodes"."parent_id" LEFT JOIN "path_nodes" AS "path_nodes.parent.parent" ON "path_nodes.parent.parent"."id" = "path_nodes.parent"."parent_id" WHERE "path_nodes"."label" = $1 AND "path_nodes.parent"."label" = $2 AND "path_nodes.parent.parent"."label" = $3"#
        )
        #expect(rendered.binds.map(\.description) == ["leaf", "branch", "root"])
    }

    @Test func aliasedSelfRelationJoinKeepsTheSourceKeyOnTheBaseRow() {
        let rendered = PathNodeModel.as("n").query().filter(PathNodeModel.Relations.parent.label == "branch").render()
        // The parent joins to the aliased base row, not to itself.
        #expect(
            rendered.sql
                == #"SELECT "n".* FROM "path_nodes" AS "n" LEFT JOIN "path_nodes" ON "path_nodes"."id" = "n"."parent_id" WHERE "path_nodes"."label" = $1"#
        )
        #expect(rendered.binds.map(\.description) == ["branch"])
    }

    // A path's join in a subquery never takes a name an enclosing query uses, so it can't hide the enclosing row: when
    // the table's name is used outside, the join is named as for a taken name (`"path_records.owner"`). A model's plain
    // column refers to the query's own table or custom join of that model, else to the nearest enclosing query that has
    // the model as its table, a custom join or its only relation join of it, else to the query's relation join of it.

    @Test func subqueryPathsStayInTheSubqueryAndPreserveCorrelatedBaseColumns() {
        let owner = PathRecordModel.Relations.owner
        let rendered = PathOrganizationModel.query()
            .filter(PathOrganizationModel.label == "north")
            .whereExists(
                PathRecordModel.query()
                    .select(PathRecordModel.id)
                    .filter(owner.organizationID == PathOrganizationModel.id)
                    .filter(owner.enabled == true)
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_organizations".* FROM "path_organizations" WHERE "path_organizations"."label" = $1 AND EXISTS (SELECT "path_records"."id" FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."organization_id" = "path_organizations"."id" AND "path_members"."enabled" = $2)"#
        )
        #expect(rendered.binds.map(\.description) == ["north", "true"])
    }

    @Test func correlatedExistsPreservesOuterColumnsWithAutomaticAndDeclaredRelationJoins() {
        for (inner, join) in [
            (PathRecordModel.query(), "LEFT JOIN"),
            (PathRecordModel.query().join(\.owner), "JOIN"),
            (PathRecordModel.query().leftJoin(\.owner), "LEFT JOIN"),
        ] {
            let rendered = PathMemberModel.query()
                .whereExists(inner.filter(PathRecordModel.Relations.owner.id == PathMemberModel.id))
                .render()
            #expect(
                rendered.sql
                    == #"SELECT "path_members".* FROM "path_members" WHERE EXISTS (SELECT "path_records".* FROM "path_records" "#
                    + join
                    + #" "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" WHERE "path_records.owner"."id" = "path_members"."id")"#
            )
            #expect(rendered.binds.isEmpty)
        }
    }

    @Test func correlatedExistsUsesTheOuterRelationJoinAlias() {
        for (outer, join) in [
            (PathRecordModel.query().join(\.owner), "JOIN"),
            (PathRecordModel.query().leftJoin(\.owner), "LEFT JOIN"),
        ] {
            let rendered =
                outer
                .whereExists(PathAssignmentModel.query().filter(PathAssignmentModel.firstID == PathMemberModel.id))
                .render()
            #expect(
                rendered.sql
                    == #"SELECT "path_records".* FROM "path_records" "# + join
                    + #" "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE EXISTS (SELECT "path_assignments".* FROM "path_assignments" WHERE "path_assignments"."first_id" = "path_members"."id")"#
            )
        }
    }

    @Test func localTableBindingsShadowOuterRelationJoinAliases() {
        let ownTable = PathRecordModel.query()
            .join(\.owner)
            .whereExists(PathMemberModel.query().filter(PathMemberModel.label == "Atlas"))
            .render()
        #expect(
            ownTable.sql
                == #"SELECT "path_records".* FROM "path_records" JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE EXISTS (SELECT "path_members".* FROM "path_members" WHERE "path_members"."label" = $1)"#
        )

        let customJoin = PathRecordModel.query()
            .join(\.owner)
            .whereExists(
                PathOrganizationModel.query()
                    .join(PathMemberModel.self, on: PathMemberModel.organizationID == PathOrganizationModel.id)
                    .whereExists(PathAssignmentModel.query().filter(PathAssignmentModel.firstID == PathMemberModel.id))
                    .filter(PathMemberModel.label == "Atlas")
            )
            .render()
        #expect(
            customJoin.sql
                == #"SELECT "path_records".* FROM "path_records" JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE EXISTS (SELECT "path_organizations".* FROM "path_organizations" JOIN "path_members" ON "path_members"."organization_id" = "path_organizations"."id" WHERE EXISTS (SELECT "path_assignments".* FROM "path_assignments" WHERE "path_assignments"."first_id" = "path_members"."id") AND "path_members"."label" = $1)"#
        )
    }

    @Test func correlatedOuterJoinAliasStaysDistinctFromAnInnerRelationPath() {
        let rendered = PathRecordModel.query()
            .join(\.owner)
            .whereExists(PathAssignmentModel.query().filter(PathAssignmentModel.Relations.first.id == PathMemberModel.id))
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE EXISTS (SELECT "path_assignments".* FROM "path_assignments" LEFT JOIN "path_members" AS "path_assignments.first" ON "path_assignments.first"."id" = "path_assignments"."first_id" WHERE "path_assignments.first"."id" = "path_members"."id")"#
        )
    }

    @Test func nestedSubqueryUsesTheNearerRelationInsteadOfTheOuterBaseTable() {
        let owner = PathRecordModel.Relations.owner
        let innermost = PathAssignmentModel.query().filter(PathAssignmentModel.firstID == PathMemberModel.id)
        for (middle, join, filter) in [
            (PathRecordModel.query().join(\.owner), "JOIN", ""),
            (PathRecordModel.query().leftJoin(\.owner), "LEFT JOIN", ""),
            (PathRecordModel.query().filter(owner.enabled == true), "LEFT JOIN", #""path_records.owner"."enabled" = $1 AND "#),
        ] {
            let rendered = PathMemberModel.query()
                .whereExists(middle.filter(owner.id == PathMemberModel.id).whereExists(innermost))
                .render()
            // The middle query correlates to the outer member; its child sees the middle query's owner as the nearest
            // member.
            #expect(
                rendered.sql
                    == #"SELECT "path_members".* FROM "path_members" WHERE EXISTS (SELECT "path_records".* FROM "path_records" "#
                    + join
                    + #" "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" WHERE "#
                    + filter
                    + #""path_records.owner"."id" = "path_members"."id" AND EXISTS (SELECT "path_assignments".* FROM "path_assignments" WHERE "path_assignments"."first_id" = "path_records.owner"."id"))"#
            )
        }
    }

    @Test func nestedSubqueryUsesTheNearerRelationInsteadOfAnOuterRelation() {
        let rendered = PathRecordModel.query()
            .join(\.owner)
            .whereExists(
                PathAssignmentModel.query()
                    .leftJoin(\.first)
                    .whereNotExists(PathOrganizationModel.query().filter(PathOrganizationModel.id == PathMemberModel.organizationID))
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE EXISTS (SELECT "path_assignments".* FROM "path_assignments" LEFT JOIN "path_members" AS "path_assignments.first" ON "path_assignments.first"."id" = "path_assignments"."first_id" WHERE NOT EXISTS (SELECT "path_organizations".* FROM "path_organizations" WHERE "path_organizations"."id" = "path_assignments.first"."organization_id"))"#
        )
    }

    @Test func ambiguousMiddleRelationsPreserveTheOuterRelationBinding() {
        let first = #"JOIN "path_members" AS "path_assignments.first" ON "path_assignments.first"."id" = "path_assignments"."first_id""#
        let second =
            #"JOIN "path_members" AS "path_assignments.second" ON "path_assignments.second"."external_ref" = "path_assignments"."second_code""#
        let innermost = PathOrganizationModel.query().filter(PathOrganizationModel.id == PathMemberModel.organizationID)
        let innermostSQL =
            #"EXISTS (SELECT "path_organizations".* FROM "path_organizations" WHERE "path_organizations"."id" = "path_members"."organization_id")"#
        for (middle, middleSQL) in [
            (PathAssignmentModel.query().join(\.first).join(\.second), "\(first) \(second) WHERE \(innermostSQL)"),
            (PathAssignmentModel.query().join(\.second).join(\.first), "\(second) \(first) WHERE \(innermostSQL)"),
            (
                PathAssignmentModel.query()
                    .filter(PathAssignmentModel.Relations.first.score > PathAssignmentModel.Relations.second.score),
                #"LEFT \#(first) LEFT \#(second) WHERE "path_assignments.first"."score" > "path_assignments.second"."score" AND \#(innermostSQL)"#
            ),
        ] {
            let rendered = PathRecordModel.query().join(\.owner).whereExists(middle.whereExists(innermost)).render()
            // Neither sibling is the one member of the middle query, so the outer owner stays the binding, whatever
            // the siblings' order and however they were joined.
            #expect(
                rendered.sql
                    == #"SELECT "path_records".* FROM "path_records" JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE EXISTS (SELECT "path_assignments".* FROM "path_assignments" "#
                    + middleSQL + ")"
            )
        }
    }

    @Test func ambiguousNestedRelationTargetsPreserveTheOuterNestedBinding() {
        let first = PathAssignmentModel.Relations.first
        let second = PathAssignmentModel.Relations.second
        let rendered = PathRecordModel.query()
            .filter(PathRecordModel.Relations.owner.organization.label == "north")
            .whereExists(
                PathAssignmentModel.query()
                    .filter(first.organization.id == second.organization.id)
                    .whereExists(PathNodeModel.query().filter(PathNodeModel.id == PathOrganizationModel.id))
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" LEFT JOIN "path_organizations" ON "path_organizations"."id" = "path_members"."organization_id" WHERE "path_organizations"."label" = $1 AND EXISTS (SELECT "path_assignments".* FROM "path_assignments" LEFT JOIN "path_members" AS "path_assignments.first" ON "path_assignments.first"."id" = "path_assignments"."first_id" LEFT JOIN "path_organizations" AS "path_assignments.first.organization" ON "path_assignments.first.organization"."id" = "path_assignments.first"."organization_id" LEFT JOIN "path_members" AS "path_assignments.second" ON "path_assignments.second"."external_ref" = "path_assignments"."second_code" LEFT JOIN "path_organizations" AS "path_assignments.second.organization" ON "path_assignments.second.organization"."id" = "path_assignments.second"."organization_id" WHERE "path_assignments.first.organization"."id" = "path_assignments.second.organization"."id" AND EXISTS (SELECT "path_nodes".* FROM "path_nodes" WHERE "path_nodes"."id" = "path_organizations"."id"))"#
        )
        #expect(rendered.binds.map(\.description) == ["north"])
    }

    @Test func correlatedNestedExistsUsesTheEnclosingRelationJoinAlias() {
        let rendered = PathRecordModel.query()
            .join(\.owner)
            .whereExists(
                PathOrganizationModel.query()
                    .whereExists(
                        PathAssignmentModel.query()
                            .filter(PathAssignmentModel.firstID == PathMemberModel.id)
                            .filter(PathMemberModel.organizationID == PathOrganizationModel.id)
                    )
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_records".* FROM "path_records" JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE EXISTS (SELECT "path_organizations".* FROM "path_organizations" WHERE EXISTS (SELECT "path_assignments".* FROM "path_assignments" WHERE "path_assignments"."first_id" = "path_members"."id" AND "path_members"."organization_id" = "path_organizations"."id"))"#
        )
    }

    @Test func correlatedNotExistsKeepsOuterFiltersAndBindOrder() {
        let owner = PathRecordModel.Relations.owner
        let rendered = PathMemberModel.query()
            .filter(PathMemberModel.label == "Atlas")
            .whereNotExists(PathRecordModel.query().filter(owner.id == PathMemberModel.id).filter(owner.score > 25))
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_members".* FROM "path_members" WHERE "path_members"."label" = $1 AND NOT EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" WHERE "path_records.owner"."id" = "path_members"."id" AND "path_records.owner"."score" > $2)"#
        )
        #expect(typedBinds(rendered) == ["String(Atlas)", "Int32(25)"])
    }

    @Test func correlatedRenamedComputedAndNullableColumnsKeepTheOuterQualifier() {
        let owner = PathRecordModel.Relations.owner
        let rendered = PathMemberModel.query()
            .whereExists(
                PathRecordModel.query()
                    .filter(owner.code == PathMemberModel.code)
                    .filter(SQL.lower(owner.label) == PathMemberModel.label)
                    .filter(PathMemberModel.score > owner.score)
                    .filter(owner.note.isDistinct(from: PathMemberModel.note))
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_members".* FROM "path_members" WHERE EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" WHERE "path_records.owner"."external_ref" = "path_members"."external_ref" AND LOWER("path_records.owner"."label") = "path_members"."label" AND "path_members"."score" > "path_records.owner"."score" AND "path_records.owner"."note" IS DISTINCT FROM "path_members"."note")"#
        )
    }

    @Test func correlatedNestedRelationKeepsTheOuterTargetTable() {
        let rendered = PathOrganizationModel.query()
            .whereExists(PathRecordModel.query().filter(PathRecordModel.Relations.owner.organization.id == PathOrganizationModel.id))
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_organizations".* FROM "path_organizations" WHERE EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" LEFT JOIN "path_organizations" AS "path_records.owner.organization" ON "path_records.owner.organization"."id" = "path_members"."organization_id" WHERE "path_records.owner.organization"."id" = "path_organizations"."id")"#
        )
    }

    @Test func correlatedColumnsCanReferenceBothEnclosingQueryLevels() {
        let owner = PathRecordModel.Relations.owner
        let rendered = PathMemberModel.query()
            .whereExists(
                PathOrganizationModel.query()
                    .whereExists(
                        PathRecordModel.query()
                            .filter(owner.id == PathMemberModel.id)
                            .filter(owner.organizationID == PathOrganizationModel.id)
                    )
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_members".* FROM "path_members" WHERE EXISTS (SELECT "path_organizations".* FROM "path_organizations" WHERE EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" WHERE "path_records.owner"."id" = "path_members"."id" AND "path_records.owner"."organization_id" = "path_organizations"."id"))"#
        )
    }

    @Test func correlatedExistsProjectionPreservesOuterColumnIdentity() {
        let hasRecords = SQL.exists(PathRecordModel.query().filter(PathRecordModel.Relations.owner.id == PathMemberModel.id))
        // A projection names all of its expressions or none, so the member's id is named too.
        let query: Projection<Int64, Bool> = PathMemberModel.query()
            .select(PathMemberModel.id.as("id"), hasRecords.as("has_records"))
        #expect(
            query.render().sql
                == #"SELECT "path_members"."id" AS "id", EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" WHERE "path_records.owner"."id" = "path_members"."id") AS "has_records" FROM "path_members""#
        )
    }

    @Test func correlatedOuterAliasCannotBeShadowedByAnAutomaticJoinAlias() {
        // Rust also tries `__dbkit_r0`, the name its allocator gives an automatic join. The table's own name is the
        // name this port gives one.
        for (alias, expected) in [
            (
                "outer_member",
                #"SELECT "outer_member".* FROM "path_members" AS "outer_member" WHERE EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."id" = "outer_member"."id")"#
            ),
            (
                "path_members",
                #"SELECT "path_members".* FROM "path_members" AS "path_members" WHERE EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" WHERE "path_records.owner"."id" = "path_members"."id")"#
            ),
        ] {
            let outer = PathMemberModel.as(alias)
            let rendered = outer.query()
                .whereExists(PathRecordModel.query().filter(PathRecordModel.Relations.owner.id == outer.id))
                .render()
            #expect(rendered.sql == expected)
        }
    }

    @Test func correlatedReusedExistsExpressionIsResolvedInEachEnclosingScope() {
        let inner = PathRecordModel.query().filter(PathRecordModel.Relations.owner.id == PathMemberModel.id)
        let standalone = inner.render().description
        let predicate = SQL.exists(inner)
        let correlated = PathMemberModel.query().filter(predicate).render()
        let local = PathOrganizationModel.query().filter(predicate).render()

        #expect(
            correlated.sql
                == #"SELECT "path_members".* FROM "path_members" WHERE EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" WHERE "path_records.owner"."id" = "path_members"."id")"#
        )
        // No enclosing query has a member here, so the plain member column still refers to this query's owner join.
        #expect(
            local.sql
                == #"SELECT "path_organizations".* FROM "path_organizations" WHERE EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."id" = "path_members"."id")"#
        )
        #expect(inner.render().description == standalone)
    }

    @Test func correlatedSiblingPathsKeepLocalComparisonsDistinctFromOuterColumns() {
        let first = PathAssignmentModel.Relations.first
        let rendered = PathMemberModel.query()
            .whereExists(
                PathAssignmentModel.query()
                    .filter(first.id == PathMemberModel.id)
                    .filter(first.score > PathAssignmentModel.Relations.second.score)
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "path_members".* FROM "path_members" WHERE EXISTS (SELECT "path_assignments".* FROM "path_assignments" LEFT JOIN "path_members" AS "path_assignments.first" ON "path_assignments.first"."id" = "path_assignments"."first_id" LEFT JOIN "path_members" AS "path_assignments.second" ON "path_assignments.second"."external_ref" = "path_assignments"."second_code" WHERE "path_assignments.first"."id" = "path_members"."id" AND "path_assignments.first"."score" > "path_assignments.second"."score")"#
        )
    }

    @Test func correlatedSubqueriesInMutationsKeepTheOuterTargetColumn() {
        let predicate = SQL.exists(PathRecordModel.query().filter(PathRecordModel.Relations.owner.id == PathMemberModel.id))
        let subquery =
            #"EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" AS "path_records.owner" ON "path_records.owner"."id" = "path_records"."owner_id" WHERE "path_records.owner"."id" = "path_members"."id")"#
        let update = PathMemberModel.update().set(PathMemberModel.enabled, to: false).filter(predicate).render()
        #expect(update.sql == #"UPDATE "path_members" SET "enabled" = $1 WHERE "# + subquery)
        let delete = PathMemberModel.delete().filter(predicate).render()
        #expect(delete.sql == #"DELETE FROM "path_members" WHERE "# + subquery)
    }

    @Test func compilingAndCloningDoNotAccumulateJoinsOrChangeAliases() {
        let query = PathRecordModel.query().filter(PathRecordModel.Relations.owner.enabled == true)
        let first = query.render().description
        #expect(query.render().description == first)
        let copy = query
        #expect(copy.render().description == first)
        let extended = copy.filter(PathRecordModel.Relations.owner.organization.label == "north").render()
        #expect(
            extended.sql
                == #"SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" LEFT JOIN "path_organizations" ON "path_organizations"."id" = "path_members"."organization_id" WHERE "path_members"."enabled" = $1 AND "path_organizations"."label" = $2"#
        )
        #expect(query.render().description == first)
    }

    @Test func correlatedExistsUsesTheOuterJoinedLoadingAlias() {
        let query: Query<PathRecordModel.Loaded<PathMemberModel?>> = PathRecordModel.query()
            .with(\.owner, .joined)
            .whereExists(PathAssignmentModel.query().filter(PathAssignmentModel.firstID == PathMemberModel.id))
        #expect(
            query.render().sql
                == #"SELECT "path_records".*, "path_members"."id" AS "owner.id", "path_members"."organization_id" AS "owner.organization_id", "path_members"."label" AS "owner.label", "path_members"."enabled" AS "owner.enabled", "path_members"."score" AS "owner.score", "path_members"."note" AS "owner.note", "path_members"."external_ref" AS "owner.external_ref" FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE EXISTS (SELECT "path_assignments".* FROM "path_assignments" WHERE "path_assignments"."first_id" = "path_members"."id")"#
        )
    }

    @Test func filteringAndJoinedLoadingShareOneJoinRegardlessOfBuilderOrder() {
        let enabled = PathRecordModel.Relations.owner.enabled == true
        let filteredFirst: Query<PathRecordModel.Loaded<PathMemberModel?>> = PathRecordModel.query()
            .filter(enabled)
            .with(\.owner, .joined)
        let loadedFirst: Query<PathRecordModel.Loaded<PathMemberModel?>> = PathRecordModel.query()
            .with(\.owner, .joined)
            .filter(enabled)
        let sql = filteredFirst.render().sql
        #expect(loadedFirst.render().sql == sql)
        #expect(
            sql
                == #"SELECT "path_records".*, "path_members"."id" AS "owner.id", "path_members"."organization_id" AS "owner.organization_id", "path_members"."label" AS "owner.label", "path_members"."enabled" AS "owner.enabled", "path_members"."score" AS "owner.score", "path_members"."note" AS "owner.note", "path_members"."external_ref" AS "owner.external_ref" FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."enabled" = $1"#
        )
    }

    @Test func explicitJoinAndJoinedLoadingShareTheRelationJoin() {
        let query: Query<PathRecordModel.Loaded<PathMemberModel?>> = PathRecordModel.query()
            .join(\.owner)
            .filter(PathRecordModel.Relations.owner.enabled == true)
            .with(\.owner, .joined)
        #expect(
            query.render().sql
                == #"SELECT "path_records".*, "path_members"."id" AS "owner.id", "path_members"."organization_id" AS "owner.organization_id", "path_members"."label" AS "owner.label", "path_members"."enabled" AS "owner.enabled", "path_members"."score" AS "owner.score", "path_members"."note" AS "owner.note", "path_members"."external_ref" AS "owner.external_ref" FROM "path_records" JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."enabled" = $1"#
        )
    }

    @Test func nestedFilterAndNestedLoaderReuseTheEntirePath() {
        let query: Query<PathRecordModel.Loaded<PathMemberModel.Loaded<PathOrganizationModel?>?>> = PathRecordModel.query()
            .filter(PathRecordModel.Relations.owner.organization.label == "north")
            .with(\.owner, .joined) { $0.with(\.organization, .joined) }
        #expect(
            query.render().sql
                == #"SELECT "path_records".*, "path_members"."id" AS "owner.id", "path_members"."organization_id" AS "owner.organization_id", "path_members"."label" AS "owner.label", "path_members"."enabled" AS "owner.enabled", "path_members"."score" AS "owner.score", "path_members"."note" AS "owner.note", "path_members"."external_ref" AS "owner.external_ref", "path_organizations"."id" AS "owner.organization.id", "path_organizations"."label" AS "owner.organization.label" FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" LEFT JOIN "path_organizations" ON "path_organizations"."id" = "path_members"."organization_id" WHERE "path_organizations"."label" = $1"#
        )
    }

    /// A count keeps the joins and counts each record once (see "Counting a query with joins" in
    /// `docs/rust-parity.md`); `exists` needs no `DISTINCT`.
    @Test func countAndExistsIncludeFilterJoinsWithoutLoadingColumns() async throws {
        let query: Query<PathRecordModel.Loaded<PathMemberModel?>> = PathRecordModel.query()
            .filter(PathRecordModel.Relations.owner.enabled == true)
            .with(\.owner, .joined)
            .limit(1)
            .offset(2)

        let count = try await firstQuery { _ = try await query.count(on: $0) }
        #expect(
            count.sql
                == #"SELECT COUNT(*) FROM (SELECT DISTINCT "path_records"."id" FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."enabled" = $1) AS "count""#
        )
        #expect(count.bindCount == 1)

        let exists = try await firstQuery { _ = try await query.exists(on: $0) }
        #expect(
            exists.sql
                == #"SELECT EXISTS (SELECT "path_records".* FROM "path_records" LEFT JOIN "path_members" ON "path_members"."id" = "path_records"."owner_id" WHERE "path_members"."enabled" = $1)"#
        )
        #expect(exists.bindCount == 1)
    }
}

/// Each bind as `<type>(<value>)`, since a bind's numeric type is the one PostgreSQL computes in.
private func typedBinds(_ rendered: RenderedSQL) -> [String] {
    rendered.binds.map { "\(type(of: $0.value))(\($0))" }
}
