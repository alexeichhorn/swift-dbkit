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

    // Waits for slice 20b: automatic_left_join_for_update_scopes_lock_to_base_table

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

    // Waits for slice 20b: custom_table_join_keeps_its_columns_when_a_relation_path_uses_the_same_table
    // Waits for slice 20b: filter_relation_join_precedes_a_custom_join_that_uses_its_alias
    // Waits for slice 20b: projection_relation_join_precedes_a_custom_left_join_that_uses_its_alias
    // Waits for slice 20b: relation_join_precedes_a_correlated_exists_in_a_custom_join_condition
    // Waits for slice 20b: relation_join_precedes_a_correlation_through_nested_join_subqueries
    // Waits for slice 20b: uncorrelated_join_subquery_keeps_its_relation_paths_local
    // Waits for slice 20b: nested_join_dependencies_move_together_without_reordering_custom_joins
    // Waits for slice 20b: dynamic_relation_column_keeps_custom_join_predicates_and_binds
    // Waits for slice 20b: dynamic_relation_key_compared_to_a_literal_is_a_custom_join
    // Waits for slice 20b: dynamic_relation_key_compared_to_another_source_column_keeps_that_column

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

    // Waits for slice 20b: aliased_self_relation_join_keeps_the_source_key_on_the_base_row
    // Waits for slice 20b: subquery_paths_stay_in_the_subquery_and_preserve_correlated_base_columns
    // Waits for slice 20b: correlated_exists_preserves_outer_columns_with_automatic_and_declared_relation_joins
    // Waits for slice 20b: correlated_exists_uses_the_outer_relation_join_alias
    // Waits for slice 20b: local_table_bindings_shadow_outer_relation_join_aliases
    // Waits for slice 20b: correlated_outer_join_alias_stays_distinct_from_an_inner_relation_path
    // Waits for slice 20b: nested_subquery_uses_the_nearer_relation_instead_of_the_outer_base_table
    // Waits for slice 20b: nested_subquery_uses_the_nearer_relation_instead_of_an_outer_relation
    // Waits for slice 20b: ambiguous_middle_relations_preserve_the_outer_relation_binding
    // Waits for slice 20b: ambiguous_nested_relation_targets_preserve_the_outer_nested_binding
    // Waits for slice 20b: correlated_nested_exists_uses_the_enclosing_relation_join_alias
    // Waits for slice 20b: correlated_not_exists_keeps_outer_filters_and_bind_order
    // Waits for slice 20b: correlated_renamed_computed_and_nullable_columns_keep_the_outer_qualifier
    // Waits for slice 20b: correlated_nested_relation_keeps_the_outer_target_table
    // Waits for slice 20b: correlated_columns_can_reference_both_enclosing_query_levels
    // Waits for slice 20b: correlated_exists_projection_preserves_outer_column_identity
    // Waits for slice 20b: correlated_outer_alias_cannot_be_shadowed_by_an_automatic_join_alias
    // Waits for slice 20b: correlated_reused_exists_expression_is_resolved_in_each_enclosing_scope
    // Waits for slice 20b: correlated_sibling_paths_keep_local_comparisons_distinct_from_outer_columns
    // Waits for slice 20b: correlated_subqueries_in_mutations_keep_the_outer_target_column

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

    // Waits for slice 20b: correlated_exists_uses_the_outer_joined_loading_alias

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

    // Waits for slice 23: count_and_exists_include_filter_joins_without_loading_columns, `count(on:)` and `exists(on:)` of
    // `PathRecordModel.query().filter(PathRecordModel.Relations.owner.enabled == true).with(\.owner, .joined).limit(1)
    // .offset(2)` keep the owner join and its filter, without the loaded columns, `LIMIT` or `OFFSET`.
}

/// Each bind as `<type>(<value>)`, since a bind's numeric type is the one PostgreSQL computes in.
private func typedBinds(_ rendered: RenderedSQL) -> [String] {
    rendered.binds.map { "\(type(of: $0.value))(\($0))" }
}
