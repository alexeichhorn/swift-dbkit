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

    @Test func correlatedExistsReturnsOnlyMembersWithMatchingRecords() async throws {
        try await withRollback { tx in
            try await setupCorrelatedRelationPaths(on: tx)

            for inner in [PathRecordModel.query(), PathRecordModel.query().join(\.owner), PathRecordModel.query().leftJoin(\.owner)] {
                let members = try await PathMemberModel.query()
                    .whereExists(inner.filter(PathRecordModel.Relations.owner.id == PathMemberModel.id))
                    .orderBy(PathMemberModel.id.asc)
                    .all(on: tx)
                #expect(members.map(\.id) == [1, 2, 3, 4])
            }
        }
    }

    @Test func correlatedNotExistsReturnsUnmatchedMembersDespiteMissingRecordOwners() async throws {
        try await withRollback { tx in
            try await setupCorrelatedRelationPaths(on: tx)

            let members = try await PathMemberModel.query()
                .whereNotExists(PathRecordModel.query().filter(PathRecordModel.Relations.owner.id == PathMemberModel.id))
                .orderBy(PathMemberModel.id.asc)
                .all(on: tx)
            // NULL and dangling owner ids in records 5 and 6 must not match any member.
            #expect(members.map(\.id) == [5])
        }
    }

    @Test func correlatedExistsProjectionIsEvaluatedForEachOuterRow() async throws {
        try await withRollback { tx in
            try await setupCorrelatedRelationPaths(on: tx)

            let hasRecords = SQL.exists(PathRecordModel.query().filter(PathRecordModel.Relations.owner.id == PathMemberModel.id))
            let rows: [(Int64, Bool)] = try await PathMemberModel.query()
                .select(PathMemberModel.id.as("id"), hasRecords.as("has_records"))
                .orderBy(PathMemberModel.id.asc)
                .all(on: tx)
            #expect(rows.map { $0.0 } == [1, 2, 3, 4, 5])
            #expect(rows.map { $0.1 } == [true, true, true, true, false])
        }
    }

    @Test func correlatedRenamedColumnAndLocalPredicateSelectTheMatchingMember() async throws {
        try await withRollback { tx in
            try await setupCorrelatedRelationPaths(on: tx)
            let owner = PathRecordModel.Relations.owner

            let members = try await PathMemberModel.query()
                .whereExists(PathRecordModel.query().filter(owner.code == PathMemberModel.code).filter(owner.score > 25))
                .orderBy(PathMemberModel.id.asc)
                .all(on: tx)
            #expect(members.map(\.id) == [1])
        }
    }

    @Test func correlatedComputedComparisonUsesTheOuterTextValue() async throws {
        try await withRollback { tx in
            try await setupCorrelatedRelationPaths(on: tx)

            let members = try await PathMemberModel.query()
                .whereExists(PathRecordModel.query().filter(SQL.lower(PathRecordModel.Relations.owner.label) == PathMemberModel.label))
                .orderBy(PathMemberModel.id.asc)
                .all(on: tx)
            // Member 5's label is member 1's in lowercase. Comparing the owner's lowercased label to its own label would
            // find nobody.
            #expect(members.map(\.id) == [5])
        }
    }

    @Test func correlatedNullableComparisonDoesNotCompareTheInnerColumnToItself() async throws {
        try await withRollback { tx in
            try await setupCorrelatedRelationPaths(on: tx)

            let members = try await PathMemberModel.query()
                .whereExists(
                    PathRecordModel.query()
                        .filter(PathRecordModel.id == 1)
                        .filter(PathRecordModel.Relations.owner.note.isDistinct(from: PathMemberModel.note))
                )
                .orderBy(PathMemberModel.id.asc)
                .all(on: tx)
            // Record 1's owner has a NULL note; only members 2 and 3 have notes.
            #expect(members.map(\.id) == [2, 3])
        }
    }

    @Test func correlatedNestedRelationExcludesAnOrganizationWithoutRecords() async throws {
        try await withRollback { tx in
            try await setupCorrelatedRelationPaths(on: tx)

            let organizations = try await PathOrganizationModel.query()
                .whereExists(PathRecordModel.query().filter(PathRecordModel.Relations.owner.organization.id == PathOrganizationModel.id))
                .orderBy(PathOrganizationModel.id.asc)
                .all(on: tx)
            #expect(organizations.map(\.id) == [1, 2])
        }
    }

    @Test func correlatedNestedExistsResolvesBothEnclosingModels() async throws {
        try await withRollback { tx in
            try await setupCorrelatedRelationPaths(on: tx)
            let owner = PathRecordModel.Relations.owner

            let members = try await PathMemberModel.query()
                .whereExists(
                    PathOrganizationModel.query()
                        .whereExists(
                            PathRecordModel.query()
                                .filter(owner.id == PathMemberModel.id)
                                .filter(owner.organizationID == PathOrganizationModel.id)
                        )
                )
                .orderBy(PathMemberModel.id.asc)
                .all(on: tx)
            // Member 4 has a record but no organization; member 5 has no record.
            #expect(members.map(\.id) == [1, 2, 3])
        }
    }

    @Test func correlatedExplicitOuterAliasIsNotShadowedByAnAutomaticAlias() async throws {
        try await withRollback { tx in
            try await setupCorrelatedRelationPaths(on: tx)

            // Rust's second alias is its allocator's `__dbkit_r0`; the table's name is the one this port's allocator uses.
            for alias in ["outer_member", "path_members"] {
                let outer = PathMemberModel.as(alias)
                let members = try await outer.query()
                    .whereExists(PathRecordModel.query().filter(PathRecordModel.Relations.owner.id == outer.id))
                    .orderBy(outer.id.asc)
                    .all(on: tx)
                #expect(members.map(\.id) == [1, 2, 3, 4], "outer alias: \(alias)")
            }
        }
    }

    @Test func correlatedSiblingPathsKeepTheirLocalComparisonAndOuterIdentity() async throws {
        try await withRollback { tx in
            try await setupCorrelatedRelationPaths(on: tx)
            let first = PathAssignmentModel.Relations.first

            let members = try await PathMemberModel.query()
                .whereExists(
                    PathAssignmentModel.query()
                        .filter(first.id == PathMemberModel.id)
                        .filter(first.score > PathAssignmentModel.Relations.second.score)
                )
                .orderBy(PathMemberModel.id.asc)
                .all(on: tx)
            #expect(members.map(\.id) == [1, 3])
        }
    }
    @Test func nestedExistsMatchesTheNearerOwnerInsteadOfTheOuterMember() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let members = try await PathMemberModel.query()
                .whereExists(
                    PathRecordModel.query()
                        .join(\.owner)
                        .filter(PathRecordModel.id == 1)
                        .whereExists(PathAssignmentModel.query().filter(PathAssignmentModel.firstID == PathMemberModel.id))
                )
                .orderBy(PathMemberModel.id.asc)
                .all(on: tx)
            // Record 1's owner has assignments, whoever the outer member is. Resolving the innermost id to the outer
            // member would exclude member 4.
            #expect(members.map(\.id) == [1, 2, 3, 4])
        }
    }

    @Test func nestedNotExistsKeepsAMissingNearerRelationInsteadOfUsingAnOuterRelation() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let records = try await PathRecordModel.query()
                .join(\.owner)
                .whereExists(
                    PathAssignmentModel.query()
                        .leftJoin(\.first)
                        .filter(PathAssignmentModel.id == 4)
                        .whereNotExists(PathOrganizationModel.query().filter(PathOrganizationModel.id == PathMemberModel.organizationID))
                )
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            // Assignment 4 has no first member, so NOT EXISTS holds for every joined record. Falling back to the record's
            // owner would leave only record 7.
            #expect(records.map(\.id) == [1, 2, 3, 4, 7])
        }
    }

    @Test func ambiguousMiddleRelationsCorrelateToTheOuterOwner() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let records = try await PathRecordModel.query()
                .join(\.owner)
                .whereExists(
                    PathAssignmentModel.query()
                        .join(\.first)
                        .join(\.second)
                        .filter(PathAssignmentModel.id == 1)
                        .whereExists(
                            PathOrganizationModel.query()
                                .filter(PathOrganizationModel.id == PathMemberModel.organizationID)
                                .filter(PathOrganizationModel.label == "north")
                        )
                )
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            // Assignment 1's members belong to different organizations. Choosing its first member would return every
            // joined record; choosing its second would return none.
            #expect(records.map(\.id) == [1, 3])
        }
    }

    @Test func ambiguousMiddleRelationsPreserveNullsInTheOuterBinding() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let records = try await PathRecordModel.query()
                .leftJoin(\.owner)
                .whereExists(
                    PathAssignmentModel.query()
                        .leftJoin(\.first)
                        .leftJoin(\.second)
                        .filter(PathAssignmentModel.id == 4)
                        .whereNotExists(PathOrganizationModel.query().filter(PathOrganizationModel.id == PathMemberModel.organizationID))
                )
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            // A missing sibling doesn't make the other one the binding. Only records without an owner or without an
            // owner's organization pass NOT EXISTS.
            #expect(records.map(\.id) == [5, 6, 7])
        }
    }

    @Test func correlatedExistsMatchesTheOuterRelationJoin() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let records = try await PathRecordModel.query()
                .join(\.owner)
                .whereExists(PathAssignmentModel.query().filter(PathAssignmentModel.firstID == PathMemberModel.id))
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            // Owner 4 has no assignment; NULL and dangling owners can't join.
            #expect(records.map(\.id) == [1, 2, 3, 4])
        }
    }

    @Test func correlatedNotExistsPreservesMissingOuterRelationJoins() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let records = try await PathRecordModel.query()
                .leftJoin(\.owner)
                .whereNotExists(PathAssignmentModel.query().filter(PathAssignmentModel.firstID == PathMemberModel.id))
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            // A NULL owner, a dangling owner and an owner without assignments all remain.
            #expect(records.map(\.id) == [5, 6, 7])
        }
    }

    @Test func correlatedExistsMatchesTheOuterJoinedLoadingRelation() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let records = try await PathRecordModel.query()
                .with(\.owner, .joined)
                .whereExists(PathAssignmentModel.query().filter(PathAssignmentModel.firstID == PathMemberModel.id))
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            #expect(records.map(\.id) == [1, 2, 3, 4])
            #expect(records.map { $0.owner?.id } == [1, 2, 1, 3])
        }
    }

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

    @Test func automaticLeftJoinForUpdateReturnsAllBaseRows() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            // No owner filter: PostgreSQL must keep the outer join and its rows without an owner.
            let rows = try await PathRecordModel.query()
                .orderBy(PathRecordModel.Relations.owner.id.asc)
                .orderBy(PathRecordModel.id.asc)
                .forUpdate()
                .all(on: tx)
            #expect(rows.map(\.id) == [1, 3, 2, 4, 7, 5, 6])
        }
    }

    @Test func countExistsOneAndPaginateUseTheSameRelationFilter() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let query = PathRecordModel.query()
                .filter(PathRecordModel.Relations.owner.enabled == true)
                .with(\.owner, .joined)
                .orderBy(PathRecordModel.id.asc)
            #expect(try await query.limit(1).offset(50).count(on: tx) == 3)
            #expect(try await query.limit(1).offset(50).exists(on: tx))
            let first = try #require(try await query.first(on: tx))
            #expect(first.id == 1)
            #expect(first.owner?.id == 1)
            let page = try await query.paginate(page: 2, perPage: 2, on: tx)
            #expect(page.total == 3)
            #expect(page.totalPages == 2)
            #expect(page.items.map(\.id) == [4])
            #expect(page.items.first?.owner?.id == 3)

            let empty = PathRecordModel.query()
                .filter(PathRecordModel.Relations.owner.score > 100)
                .with(\.owner, .joined)
            #expect(try await empty.count(on: tx) == 0)
            #expect(try await empty.exists(on: tx) == false)
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

    @Test func aliasedSelfRelationFiltersByEachBaseRowsParent() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let base = PathNodeModel.as("n")
            var results: [String: [Int64]] = [:]
            for label in ["branch", "cycle"] {
                let rows = try await base.query()
                    .filter(PathNodeModel.Relations.parent.label == label)
                    .orderBy(base.id.asc)
                    .all(on: tx)
                results[label] = rows.map(\.id)
            }
            // A parent joined to itself would lose the leaf and make the cycle match every base row.
            #expect(results == ["branch": [3], "cycle": [5]])
        }
    }

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

            let custom = try await PathRecordModel.query()
                .leftJoin(PathMemberModel.self, on: PathMemberModel.id == PathRecordModel.ownerID && PathMemberModel.score > 25)
                .filter(PathMemberModel.note.isNull)
                .filter(PathRecordModel.Relations.owner.code == "c")
                .all(on: tx)
            #expect(custom.map(\.id) == [4])
        }
    }

    @Test func customJoinCanUseARelationDiscoveredInAFilterInEitherBuilderOrder() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let on = PathOrganizationModel.id == PathMemberModel.organizationID && PathOrganizationModel.label == "north"
            let enabled = PathRecordModel.Relations.owner.enabled == true
            for query in [
                PathRecordModel.query().join(PathOrganizationModel.self, on: on).filter(enabled),
                PathRecordModel.query().filter(enabled).join(PathOrganizationModel.self, on: on),
            ] {
                let records = try await query.orderBy(PathRecordModel.id.asc).all(on: tx)
                // Both the custom organization condition and the owner filter apply.
                #expect(records.map(\.id) == [1, 3])
            }
        }
    }

    @Test func customJoinExistsCanCorrelateToAnAutomaticallyJoinedOwner() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let records = try await PathRecordModel.query()
                .join(
                    PathOrganizationModel.self,
                    on: PathOrganizationModel.id == 1
                        && SQL.exists(
                            PathAssignmentModel.query()
                                .filter(PathAssignmentModel.firstID == PathMemberModel.id)
                                .filter(PathAssignmentModel.secondCode == "b")
                        )
                )
                .filter(PathRecordModel.Relations.owner.enabled == true)
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            // Owners 1 and 3 are enabled and have matching assignments. Joining one organization row also checks that
            // EXISTS doesn't duplicate records.
            #expect(records.map(\.id) == [1, 3, 4])
        }
    }

    @Test func customLeftJoinNotExistsPreservesMissingOwnerRows() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let rows = try await PathRecordModel.query()
                .leftJoin(
                    PathOrganizationModel.self,
                    on: PathOrganizationModel.id == 1
                        && !SQL.exists(PathAssignmentModel.query().filter(PathAssignmentModel.firstID == PathMemberModel.id))
                )
                .select(
                    PathRecordModel.id.as("id"),
                    PathRecordModel.Relations.owner.id.as("owner_id"),
                    PathOrganizationModel.id.as("organization_id")
                )
                .orderBy(PathRecordModel.id.asc)
                .all(as: OwnerOrganization.self, on: tx)
            // The custom join matches when the owner is missing or has no assignments. Owners with assignments remain,
            // with no organization.
            #expect(rows.map(\.id) == [1, 2, 3, 4, 5, 6, 7])
            #expect(rows.map(\.ownerID) == [1, 2, 1, 3, nil, nil, 4])
            #expect(rows.map(\.organizationID) == [nil, nil, nil, nil, 1, 1, 1])
        }
    }

    @Test func customLeftJoinCanUseAProjectionRelationAndPreserveMissingTargets() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let rows = try await PathRecordModel.query()
                .leftJoin(PathOrganizationModel.self, on: PathOrganizationModel.id == PathMemberModel.organizationID)
                .select(
                    PathRecordModel.id.as("id"),
                    PathRecordModel.Relations.owner.label.as("owner_label"),
                    PathOrganizationModel.label.as("organization_label")
                )
                .orderBy(PathRecordModel.id.asc)
                .all(as: OwnerOrganizationLabels.self, on: tx)
            // Missing owners and an owner with a dangling organization survive both left joins.
            #expect(rows.map(\.id) == [1, 2, 3, 4, 5, 6, 7])
            #expect(rows.map(\.ownerLabel) == ["Atlas", "Birch", "Atlas", "Cedar", nil, nil, "Delta"])
            #expect(rows.map(\.organizationLabel) == ["north", "south", "north", "south", nil, nil, nil])
        }
    }

    // Rust's two "dynamic" tests build the path column from a column and relation descriptors; Swift spells it only
    // through `Relations`.

    @Test func customLeftJoinWithADynamicRelationColumnPreservesMatchesAndMissingOwners() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let records = try await PathRecordModel.query()
                .leftJoin(PathMemberModel.self, on: PathRecordModel.Relations.owner.enabled == true)
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            // An enabled owner matches all four members of the custom join. Disabled, NULL and dangling owners remain
            // once because it is a left join.
            #expect(records.map(\.id) == [1, 1, 1, 1, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 6, 7])
        }
    }

    @Test func customInnerJoinWithADynamicRelationKeyUsesTheRequestedSourceColumn() async throws {
        try await withRollback { tx in
            try await setupRelationPaths(on: tx)

            let records = try await PathRecordModel.query()
                .join(PathMemberModel.self, on: PathRecordModel.Relations.owner.id == PathRecordModel.id)
                .orderBy(PathRecordModel.id.asc)
                .all(on: tx)
            // Only records 1 and 2 have owner.id == record.id; each matches all four members.
            #expect(records.map(\.id) == [1, 1, 1, 1, 2, 2, 2, 2])
        }
    }

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

            let organizations = try await PathOrganizationModel.query()
                .whereExists(
                    PathRecordModel.query()
                        .select(PathRecordModel.id)
                        .filter(owner.organizationID == PathOrganizationModel.id)
                        .filter(owner.score > 25)
                )
                .all(on: tx)
            #expect(organizations.map(\.id) == [1])
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

/// A projection row whose plain organization column may be NULL from a left join, which a tuple typed by the model's
/// required column can't decode.
private struct OwnerOrganization: Decodable {
    let id: Int64
    let ownerID: Int64?
    let organizationID: Int64?
}

private struct OwnerOrganizationLabels: Decodable {
    let id: Int64
    let ownerLabel: String?
    let organizationLabel: String?
}
