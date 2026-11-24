import DBKit
import Testing

/// rust-dbkit's `integration_relation_paths.rs`, on the models and rows of `setupRelationPaths(on:)`.
@Suite struct IntegrationRelationPathsTests {
    @Test func scalarLeftArithmeticEvaluatesInOrderAndPreservesMissingRelations() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)
            let owner = PathRecordModel.Relations.owner

            let rows: [(Int64, Int32?, Int32?, Int32?, Double?, Int64?)] = try await PathRecordModel.query()
                .select(
                    PathRecordModel.id,
                    Int32(1) + owner.score,
                    Int32(100) - owner.score,
                    Int32(2) * owner.score,
                    Double(15) / owner.score,
                    Int64(10) - owner.organization.id
                )
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(rows.map { $0.0 } == [1, 2, 3, 4, 5, 6, 7])
            #expect(rows.map { $0.1 } == [31, 11, 31, 21, nil, nil, 6])
            #expect(rows.map { $0.2 } == [70, 90, 70, 80, nil, nil, 95])
            #expect(rows.map { $0.3 } == [60, 20, 60, 40, nil, nil, 10])
            #expect(rows.map { $0.4 } == [0.5, 1.5, 0.5, 0.75, nil, nil, 3.0])
            #expect(rows.map { $0.5 } == [9, 8, 9, 8, nil, nil, nil])

            let filtered = try await PathRecordModel.query()
                .filter(Int32(100) - owner.score > Int32(70))
                .orderBy((Int32(100) - owner.score).asc)
                .all(on: tx)
            #expect(filtered.map(\.id) == [4, 2, 7])
        }
    }

    @Test func scalarLeftBitwiseAndShiftOperatorsPreserveValuesAndNulls() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)
            let owner = PathRecordModel.Relations.owner

            let rows: [(Int64, Int32?, Int32?, Int32?, Int64?, Int64?)] = try await PathRecordModel.query()
                .select(
                    PathRecordModel.id,
                    Int32(7) & owner.score,
                    Int32(8) | owner.score,
                    Int32(3) ^ owner.score,
                    Int64(1) << owner.score,
                    Int64(1024) >> owner.score
                )
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(rows.map { $0.0 } == [1, 2, 3, 4, 5, 6, 7])
            #expect(rows.map { $0.1 } == [6, 2, 6, 4, nil, nil, 5])
            #expect(rows.map { $0.2 } == [30, 10, 30, 28, nil, nil, 13])
            #expect(rows.map { $0.3 } == [29, 9, 29, 23, nil, nil, 6])
            #expect(rows.map { $0.4 } == [1_073_741_824, 1024, 1_073_741_824, 1_048_576, nil, nil, 32])
            #expect(rows.map { $0.5 } == [0, 1, 0, 0, nil, nil, 32])
        }
    }

    @Test func scalarLeftOperatorsPreserveNullFieldsOnExistingSelfRelations() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)
            let parent = PathNodeModel.Relations.parent

            let rows: [(Int64, Int64?, Int64?)] = try await PathNodeModel.query()
                .select(PathNodeModel.id, Int64(1) + parent.parentID, Int64(7) & parent.parentID)
                .orderBy(PathNodeModel.id.asc)
                .all(on: tx)
            // Node 2 has a parent whose parent_id is NULL; nodes 1 and 4 have no parent row.
            #expect(rows.map { $0.0 } == [1, 2, 3, 4, 5])
            #expect(rows.map { $0.1 } == [nil, nil, 2, nil, 6])
            #expect(rows.map { $0.2 } == [nil, nil, 1, nil, 5])
        }
    }

    // Waits for slice 20b: correlated_exists_returns_only_members_with_matching_records
    // Waits for slice 20b: correlated_not_exists_returns_unmatched_members_despite_missing_record_owners
    // Waits for slice 20b: correlated_exists_projection_is_evaluated_for_each_outer_row
    // Waits for slice 20b: correlated_renamed_column_and_local_predicate_select_the_matching_member
    // Waits for slice 20b: correlated_computed_comparison_uses_the_outer_text_value
    // Waits for slice 20b: correlated_nullable_comparison_does_not_compare_the_inner_column_to_itself
    // Waits for slice 20b: correlated_nested_relation_excludes_an_organization_without_records
    // Waits for slice 20b: correlated_nested_exists_resolves_both_enclosing_models
    // Waits for slice 20b: correlated_explicit_outer_alias_is_not_shadowed_by_an_automatic_alias
    // Waits for slice 20b: correlated_sibling_paths_keep_their_local_comparison_and_outer_identity
    // Waits for slice 20b: nested_exists_matches_the_nearer_owner_instead_of_the_outer_member
    // Waits for slice 20b: nested_not_exists_keeps_a_missing_nearer_relation_instead_of_using_an_outer_relation
    // Waits for slice 20b: ambiguous_middle_relations_correlate_to_the_outer_owner
    // Waits for slice 20b: ambiguous_middle_relations_preserve_nulls_in_the_outer_binding
    // Waits for slice 20b: correlated_exists_matches_the_outer_relation_join
    // Waits for slice 20b: correlated_not_exists_preserves_missing_outer_relation_joins
    // Waits for slice 20b: correlated_exists_matches_the_outer_joined_loading_relation

    @Test func filteringIsIndependentOfLoadingStrategy() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let query = PathRecordModel.query()
                .filter(PathRecordModel.Relations.owner.enabled == true)
                .orderBy(PathRecordModel.id.asc)
            // A path doesn't load its relation.
            let bare: [PathRecordModel] = try await query.all(on: tx)
            #expect(bare.map(\.id) == [1, 3, 4])

            let joined = try await query.with(\.owner, .joined).all(on: tx)
            let selectIn = try await query.with(\.owner, .selectIn).all(on: tx)
            for rows in [joined, selectIn] {
                #expect(rows.map(\.id) == [1, 3, 4])
                #expect(rows.map { $0.owner?.id } == [1, 1, 3])
                #expect(rows.allSatisfy { $0.owner?.enabled == true })
            }
        }
    }

    @Test func outerJoinsPreserveMissingRowsInOrNullAndProjectionExpressions() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)
            let owner = PathRecordModel.Relations.owner

            let rows = try await PathRecordModel.query()
                .filter(PathRecordModel.enabled == true || owner.enabled == true)
                .with(\.owner, .joined)
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(rows.map(\.id) == [1, 2, 3, 4, 5])
            #expect(rows.last?.owner == nil)

            let missing = try await PathRecordModel.query()
                .filter(owner.id.isNull)
                .with(\.owner, .joined)
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(missing.map(\.id) == [5, 6])
            #expect(missing.allSatisfy { $0.owner == nil })

            let disabled = try await PathRecordModel.query()
                .filter(!(owner.enabled == true))
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(disabled.map(\.id) == [2, 7])

            let projected: [(Int64, Bool?, String?)] = try await PathRecordModel.query()
                .select(PathRecordModel.id, owner.enabled == true, owner.note)
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(projected.map { $0.0 } == [1, 2, 3, 4, 5, 6, 7])
            #expect(projected.map { $0.1 } == [true, false, true, true, nil, nil, false])
            #expect(projected.map { $0.2 } == [nil, "memo", nil, "", nil, nil, nil])
        }
    }

    @Test func expressionsRenamedColumnsAndNullChecksUseTheRelatedRow() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)
            let owner = PathRecordModel.Relations.owner

            let rows = try await PathRecordModel.query()
                .filter(SQL.lower(owner.label) == "atlas")
                .filter(owner.score + 5 >= 35)
                .filter(owner.code.in(["a", "b"]))
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(rows.map(\.id) == [1, 3])

            let nullNotes = try await PathRecordModel.query()
                .filter(owner.note.isNull)
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(nullNotes.map(\.id) == [1, 3, 5, 6, 7])

            let none = try await PathRecordModel.query().filter(owner.code == "a' OR true --").all(on: tx)
            #expect(none.isEmpty)
        }
    }

    @Test func relatedOrderingRunsBeforeLimitAndKeepsMissingRows() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let query = PathRecordModel.query()
                .orderBy(PathRecordModel.Relations.owner.label.asc)
                .orderBy(PathRecordModel.id.asc)
            let all = try await query.all(on: tx)
            #expect(all.map(\.id) == [1, 3, 2, 4, 7, 5, 6])
            let page = try await query.with(\.owner, .joined).limit(2).offset(1).all(on: tx)
            #expect(page.map(\.id) == [3, 2])
            #expect(page.map { $0.owner?.label } == ["Atlas", "Birch"])
        }
    }

    // Waits for slice 20b: automatic_left_join_for_update_returns_all_base_rows

    @Test func countExistsOneAndPaginateUseTheSameRelationFilter() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let query = PathRecordModel.query()
                .filter(PathRecordModel.Relations.owner.enabled == true)
                .with(\.owner, .joined)
                .orderBy(PathRecordModel.id.asc)
            // Waits for slice 23: `count(on:)` of `query.limit(1).offset(50)` is 3 and its `exists(on:)` is true.
            let first = try #require(try await query.first(on: tx))
            #expect(first.id == 1)
            #expect(first.owner?.id == 1)
            // Waits for slice 23: `paginate(page: 2, perPage: 2, on:)` has a total of 3 in 2 pages, and its one item
            // is record 4 with owner 3.

            let empty = PathRecordModel.query()
                .filter(PathRecordModel.Relations.owner.score > 100)
                .with(\.owner, .joined)
            // Waits for slice 23: `count(on:)` of `empty` is 0 and its `exists(on:)` is false.
            #expect(try await empty.first(on: tx) == nil)
            #expect(try await empty.all(on: tx).isEmpty)
        }
    }

    @Test func nestedFiltersAndBothNestedLoadingStrategiesAgree() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)
            let organization = PathRecordModel.Relations.owner.organization

            let query = PathRecordModel.query()
                .filter(organization.label == "north")
                .orderBy(PathRecordModel.id.asc)
            let joined: [PathRecordModel.Loaded<PathMemberModel.Loaded<PathOrganizationModel?>?>] =
                try await query
                .with(\.owner, .joined) { $0.with(\.organization, .joined) }
                .all(on: tx)
            let selectIn: [PathRecordModel.Loaded<PathMemberModel.Loaded<PathOrganizationModel?>?>] =
                try await query
                .with(\.owner, .selectIn) { $0.with(\.organization, .selectIn) }
                .all(on: tx)
            for rows in [joined, selectIn] {
                #expect(rows.map(\.id) == [1, 3])
                #expect(rows.allSatisfy { $0.owner?.organization?.label == "north" })
            }

            let missing = try await PathRecordModel.query()
                .filter(organization.id.isNull)
                .with(\.owner, .joined) { $0.with(\.organization, .joined) }
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(missing.map(\.id) == [5, 6, 7])
            #expect(missing[0].owner == nil && missing[1].owner == nil)
            #expect(missing[2].owner?.id == 4)
            #expect(missing[2].owner?.organization == nil)
        }
    }

    @Test func siblingRelationsFilterAndDecodeIndependentlyInBothLoaders() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)
            let first = PathAssignmentModel.Relations.first
            let second = PathAssignmentModel.Relations.second

            let query = PathAssignmentModel.query()
                .filter(first.enabled == true)
                .filter(second.enabled == false)
                .filter(first.score > second.score)
                .orderBy(PathAssignmentModel.id.asc)
            let joined: [PathAssignmentModel.Loaded<PathMemberModel?, PathMemberModel?>] =
                try await query
                .with(\.first, .joined)
                .with(\.second, .joined)
                .all(on: tx)
            let selectIn: [PathAssignmentModel.Loaded<PathMemberModel?, PathMemberModel?>] =
                try await query
                .with(\.second)
                .with(\.first)
                .all(on: tx)
            for rows in [joined, selectIn] {
                #expect(rows.map(\.id) == [1, 7])
                #expect(rows.map { $0.first?.id } == [1, 3])
                #expect(rows.allSatisfy { $0.second?.id == 2 })
            }
        }
    }

    @Test func missingOrEqualSiblingTargetsDoNotOverwriteEachOther() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let query = PathAssignmentModel.query().orderBy(PathAssignmentModel.id.asc)
            let joined: [PathAssignmentModel.Loaded<PathMemberModel?, PathMemberModel?>] =
                try await query
                .with(\.second, .joined)
                .with(\.first, .joined)
                .all(on: tx)
            let selectIn: [PathAssignmentModel.Loaded<PathMemberModel?, PathMemberModel?>] =
                try await query
                .with(\.first)
                .with(\.second)
                .all(on: tx)
            for rows in [joined, selectIn] {
                #expect(rows.map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8])
                #expect(rows.map { $0.first?.id } == [1, 2, 1, nil, 1, nil, 3, 2])
                #expect(rows.map { $0.second?.id } == [2, 1, 1, 1, nil, nil, 2, 2])
            }
        }
    }

    @Test func nestedSiblingsKeepTheirOwnOrganizations() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let rows:
                [PathAssignmentModel.Loaded<
                    PathMemberModel.Loaded<PathOrganizationModel?>?, PathMemberModel.Loaded<PathOrganizationModel?>?
                >] =
                    try await PathAssignmentModel.query()
                    .filter(PathAssignmentModel.Relations.first.organization.label == "north")
                    .filter(PathAssignmentModel.Relations.second.organization.label == "south")
                    .with(\.first, .joined) { $0.with(\.organization, .joined) }
                    .with(\.second, .joined) { $0.with(\.organization, .joined) }
                    .all(on: tx)
            #expect(rows.map(\.id) == [1])
            #expect(rows.first?.first?.organization?.id == 1)
            #expect(rows.first?.second?.organization?.id == 2)
        }
    }

    @Test func selfRelationsSupportFiniteDepthMissingParentsAndCycles() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let leaf: PathNodeModel.Loaded<PathNodeModel.Loaded<PathNodeModel?>?> = try #require(
                try await PathNodeModel.query()
                    .filter(PathNodeModel.Relations.parent.parent.label == "root")
                    .with(\.parent, .joined) { $0.with(\.parent, .joined) }
                    .first(on: tx))
            #expect(leaf.id == 3)
            let parent = try #require(leaf.parent)
            #expect(parent.id == 2)
            #expect(parent.parent?.id == 1)

            let query = PathNodeModel.query().orderBy(PathNodeModel.id.asc)
            let joined = try await query.with(\.parent, .joined) { $0.with(\.parent, .joined) }.all(on: tx)
            let selectIn = try await query.with(\.parent, .selectIn) { $0.with(\.parent, .selectIn) }.all(on: tx)
            for rows in [joined, selectIn] {
                #expect(rows.count == 5)
                #expect(rows[0].parent == nil)
                #expect(rows[3].parent == nil)
                let cycle = try #require(rows[4].parent)
                #expect(cycle.id == 5)
                #expect(cycle.parent?.id == 5)
            }
        }
    }

    // Waits for slice 20b: aliased_self_relation_filters_by_each_base_rows_parent

    @Test func explicitInnerJoinsAndExistingTableColumnFiltersStillWork() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let inner = try await PathRecordModel.query()
                .join(\.owner)
                .with(\.owner, .joined)
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(inner.map(\.id) == [1, 2, 3, 4, 7])

            let legacy = try await PathRecordModel.query()
                .with(\.owner, .joined)
                .filter(PathMemberModel.enabled == true)
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            let mixed = try await PathRecordModel.query()
                .join(\.owner)
                .filter(PathMemberModel.enabled == true)
                .filter(PathRecordModel.Relations.owner.code == "a")
                .with(\.owner, .joined)
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(legacy.map(\.id) == [1, 3, 4])
            #expect(mixed.map(\.id) == [1, 3])

            // Waits for slice 20b: the records left-joined to members with
            // `PathMemberModel.id == PathRecordModel.ownerID && PathMemberModel.score > 25`, filtered by
            // `PathMemberModel.note.isNull` and `PathRecordModel.Relations.owner.code == "c"`, are `[4]`.
        }
    }

    // Waits for slice 20b: custom_join_can_use_a_relation_discovered_in_a_filter_in_either_builder_order
    // Waits for slice 20b: custom_join_exists_can_correlate_to_an_automatically_joined_owner
    // Waits for slice 20b: custom_left_join_not_exists_preserves_missing_owner_rows
    // Waits for slice 20b: custom_left_join_can_use_a_projection_relation_and_preserve_missing_targets
    // Waits for slice 20b: custom_left_join_with_a_dynamic_relation_column_preserves_matches_and_missing_owners
    // Waits for slice 20b: custom_inner_join_with_a_dynamic_relation_key_uses_the_requested_source_column

    @Test func groupedProjectionsAndCorrelatedExistsResolvePathsInTheirQuery() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)
            let owner = PathRecordModel.Relations.owner

            let counts: [(Bool?, Int64)] = try await PathRecordModel.query()
                .select(owner.enabled, SQL.count(PathRecordModel.id))
                .groupBy(owner.enabled)
                .having(SQL.count(PathRecordModel.id) > 1)
                .orderBy(owner.enabled.asc)
                .all(on: tx)
            #expect(counts.map { $0.0 } == [false, true, nil])
            #expect(counts.map { $0.1 } == [2, 3, 2])

            // Waits for slice 20b: the organizations with a record whose owner belongs to them and scores over 25,
            // `PathOrganizationModel.query().whereExists(PathRecordModel.query().select(PathRecordModel.id)
            // .filter(owner.organizationID == PathOrganizationModel.id).filter(owner.score > 25))`, are `[1]`.
        }
    }

    @Test func explicitLoadAndPartialUnloadPreserveSiblingRelationIdentity() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let bare = try #require(try await PathAssignmentModel.query().filter(PathAssignmentModel.id == 1).first(on: tx))
            let second: PathAssignmentModel.Loaded<NotLoaded, PathMemberModel?> = try await bare.load(\.second, on: tx)
            #expect(second.second?.id == 2)
            let both: PathAssignmentModel.Loaded<PathMemberModel?, PathMemberModel?> = try await second.load(\.first, on: tx)
            #expect(both.first?.id == 1)
            #expect(both.second?.id == 2)
            // Rust's conversion of `both` to rows with only one relation loaded is left out; see "Converting a loaded
            // row to a type with fewer loaded relations" in docs/rust-parity.md.
        }
    }
}
