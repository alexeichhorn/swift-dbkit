import DBKit
import Foundation
import Testing

@Suite struct IntegrationPostgresTests {
    @Test func insertUpdateDeleteRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Alex", email: "a@b.com")
            #expect(user.id > 0)
            #expect(user.name == "Alex")

            let updated = try await UserModel.update()
                .set(UserModel.name, to: "Updated")
                .filter(UserModel.id == user.id)
                .returningAll()
                .all(on: tx)
            #expect(updated.count == 1)
            #expect(updated.first?.name == "Updated")

            let deleted = try await UserModel.delete().filter(UserModel.id == user.id).execute(on: tx)
            #expect(deleted == 1)
            #expect(try await UserModel.query().all(on: tx).isEmpty)
        }
    }

    @Test func insertManyInsertsMultipleRows() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let inserted = try await UserModel.insert([
                UserModel.Insert(name: "Alpha", email: "alpha@db.com"),
                UserModel.Insert(name: "Beta", email: "beta@db.com"),
            ])
            .execute(on: tx)
            #expect(inserted == 2)

            let users = try await UserModel.query().orderBy(UserModel.id.asc).all(on: tx)
            #expect(users.map(\.name) == ["Alpha", "Beta"])
        }
    }

    @Test func onConflictDoNothingIgnoresDuplicateCompositeKey() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let original = try await seedRunPayload(on: tx, 100, 200, payload: "payload-v1", source: "ingest-a", version: 1)
            #expect(original.payload == "payload-v1")

            let affected = try await RunPayloadModel.insert(
                RunPayloadModel.Insert(targetID: 100, runID: 200, payload: "payload-v2", source: "ingest-b", version: 2)
            )
            .onConflictDoNothing(RunPayloadModel.targetID, RunPayloadModel.runID)
            .execute(on: tx)
            #expect(affected == 0)

            let rows = try await runPayloads(100, 200, on: tx)
            #expect(rows.count == 1)
            #expect(rows.first?.payload == "payload-v1")
            #expect(rows.first?.source == "ingest-a")
            #expect(rows.first?.version == 1)
        }
    }

    @Test func onConflictDoNothingWithReturningAllReturnsNoneOnConflict() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedRunPayload(on: tx, 10, 20, payload: "payload-v1", source: "ingest-a", version: 1)

            let row = try await RunPayloadModel.insert(
                RunPayloadModel.Insert(targetID: 10, runID: 20, payload: "payload-v2", source: "ingest-b", version: 2)
            )
            .onConflictDoNothing(RunPayloadModel.targetID, RunPayloadModel.runID)
            .returningAll()
            .first(on: tx)
            #expect(row == nil)
        }
    }

    @Test func onConflictDoUpdateUpdatesOnlySelectedColumnsOnConflict() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedRunPayload(on: tx, 500, 600, payload: "payload-v1", source: "ingest-a", version: 1)

            let affected = try await RunPayloadModel.insert(
                RunPayloadModel.Insert(targetID: 500, runID: 600, payload: "payload-v2", source: "ingest-b", version: 2)
            )
            .onConflict(RunPayloadModel.targetID, RunPayloadModel.runID, doUpdate: RunPayloadModel.payload, RunPayloadModel.version)
            .execute(on: tx)
            #expect(affected == 1)

            let rows = try await runPayloads(500, 600, on: tx)
            #expect(rows.count == 1)
            #expect(rows.first?.payload == "payload-v2")
            #expect(rows.first?.version == 2)
            #expect(rows.first?.source == "ingest-a")
        }
    }

    @Test func onConflictDoUpdateInsertsWhenNoConflictExists() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let affected = try await RunPayloadModel.insert(
                RunPayloadModel.Insert(targetID: 700, runID: 800, payload: "payload-v1", source: "ingest-a", version: 1)
            )
            .onConflict(RunPayloadModel.targetID, RunPayloadModel.runID, doUpdate: RunPayloadModel.payload, RunPayloadModel.version)
            .execute(on: tx)
            #expect(affected == 1)

            let rows = try await runPayloads(700, 800, on: tx)
            #expect(rows.count == 1)
            #expect(rows.first?.payload == "payload-v1")
            #expect(rows.first?.source == "ingest-a")
            #expect(rows.first?.version == 1)
        }
    }

    @Test func modelDeleteRemovesRow() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Delete", email: "delete2@db.com")
            let deleted = try await user.delete(on: tx)
            #expect(deleted == 1)
            #expect(try await UserModel.find(user.id, on: tx) == nil)
        }
    }

    @Test func activeInsertRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            var active = ActiveModel<UserModel>()
            active.name = "Active"
            active.email = "active@db.com"

            let inserted: UserModel = try await active.save(on: tx)
            #expect(inserted.id > 0)
            #expect(inserted.name == "Active")
            #expect(inserted.email == "active@db.com")
        }
    }

    @Test func activeSaveInsertsNewActiveEvenWithPrimaryKeySet() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            var active = ActiveModel<OrderLineModel>()
            active.orderID = 7
            active.lineID = 8
            active.note = "Saved"

            let inserted = try await active.save(on: tx)
            #expect(inserted.orderID == 7)
            #expect(inserted.lineID == 8)
            #expect(inserted.note == "Saved")

            let fetched = try #require(try await orderLine(7, 8, on: tx))
            #expect(fetched.note == "Saved")
        }
    }

    @Test func activeSaveUpdatesLoadedModels() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Before Save", email: "before-save@db.com")
            var active = user.active()
            active.name = "After Save"

            let saved = try await active.save(on: tx)
            #expect(saved.id == user.id)
            #expect(saved.name == "After Save")
            #expect(saved.email == user.email)

            let fetched = try #require(try await UserModel.find(user.id, on: tx))
            #expect(fetched.name == "After Save")
            #expect(fetched.email == user.email)
        }
    }

    @Test func activeSaveLoadedWithoutChangesIsNoop() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "No Change", email: "no-change@db.com")
            let active = user.active()

            let saved = try await active.save(on: tx)
            #expect(saved.id == user.id)
            #expect(saved.name == "No Change")
            #expect(saved.email == user.email)

            let fetched = try #require(try await UserModel.find(user.id, on: tx))
            #expect(fetched.name == "No Change")
            #expect(fetched.email == user.email)
        }
    }

    @Test func activeSaveMissingRequiredFieldsErrorsOnInsert() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            var active = ActiveModel<UserModel>()
            active.name = "Missing email"

            await #expect(throws: (any Error).self) { try await active.save(on: tx) }
        }
    }

    /// rust-dbkit never writes key columns and reports the row as not found instead; see `docs/rust-parity.md`.
    @Test func activeSaveChangingACompositeKeyColumnMovesTheRow() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row = try await seedOrderLine(on: tx, 5, 5, note: "Orig")
            var active = row.active()
            active.lineID = 9
            active.note = "Changed"

            let saved = try await active.save(on: tx)
            #expect(saved.orderID == 5 && saved.lineID == 9 && saved.note == "Changed")

            #expect(try await orderLine(5, 5, on: tx) == nil)
            #expect(try await orderLine(5, 9, on: tx)?.note == "Changed")
        }
    }

    @Test func activeUpdateFromLoaded() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Before", email: "before@db.com")
            var active = user.active()
            active.name = "After"

            let updated: UserModel = try await active.update(on: tx)
            #expect(updated.id == user.id)
            #expect(updated.name == "After")
            #expect(updated.email == user.email)
        }
    }

    /// A concurrent update to another column survives, since an active model writes only the columns assigned on it.
    @Test func activeUpdateDoesNotOverwriteOtherFields() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Before", email: "before@db.com")
            var active = user.active()

            try await UserModel.update().set(UserModel.email, to: "updated@db.com").filter(UserModel.id == user.id).execute(on: tx)

            active.name = "After"
            _ = try await active.update(on: tx)

            let fetched = try #require(try await UserModel.find(user.id, on: tx))
            #expect(fetched.name == "After")
            #expect(fetched.email == "updated@db.com")
        }
    }

    @Test func activeUpdateSetNull() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row = try #require(
                try await NullableRowModel.insert(NullableRowModel.Insert(note: "note")).returningAll().first(on: tx))
            var active = row.active()
            active.note = nil

            let updated: NullableRowModel = try await active.update(on: tx)
            #expect(updated.id == row.id)
            #expect(updated.note == nil)
        }
    }

    /// Updating a new active model is a mistake; whether it traps or throws, it never succeeds.
    @Test func activeUpdateRequiresPrimaryKey() async {
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var active = ActiveModel<UserModel>()
                active.name = "No PK"
                active.email = "no-pk@db.com"
                _ = try await active.update(on: tx)
            }
        }
    }

    @Test func activeUpdateUsesOnlyPrimaryKeyFilter() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Before", email: "before@db.com")
            let untouched = try await seedUser(on: tx, name: "Other", email: "other@db.com")
            var active = user.active()
            active.name = "After"
            active.email = "after@db.com"

            let updated = try await active.update(on: tx)
            #expect(updated.id == user.id)
            #expect(updated.name == "After")
            #expect(updated.email == "after@db.com")

            let fetched = try #require(try await UserModel.find(user.id, on: tx))
            #expect(fetched.name == "After")
            #expect(fetched.email == "after@db.com")

            let other = try #require(try await UserModel.find(untouched.id, on: tx))
            #expect(other.name == "Other")
            #expect(other.email == "other@db.com")
        }
    }

    @Test func compositePrimaryKeyActiveUpdateUsesBothKeys() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let first = try await seedOrderLine(on: tx, 1, 1, note: "A")
            _ = try await seedOrderLine(on: tx, 1, 2, note: "B")
            _ = try await seedOrderLine(on: tx, 2, 1, note: "C")

            var active = first.active()
            active.note = "A1"
            let updated = try await active.update(on: tx)
            #expect(updated.orderID == 1)
            #expect(updated.lineID == 1)
            #expect(updated.note == "A1")

            #expect(try await orderLine(1, 1, on: tx)?.note == "A1")
            #expect(try await orderLine(1, 2, on: tx)?.note == "B")
            #expect(try await orderLine(2, 1, on: tx)?.note == "C")
        }
    }

    @Test func compositePrimaryKeyActiveUpdateRequiresAllKeys() async {
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var missingLine = ActiveModel<OrderLineModel>()
                missingLine.orderID = 1
                missingLine.note = "Missing line"
                _ = try await missingLine.update(on: tx)
            }
        }
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var missingOrder = ActiveModel<OrderLineModel>()
                missingOrder.lineID = 1
                missingOrder.note = "Missing order"
                _ = try await missingOrder.update(on: tx)
            }
        }
    }

    /// Each insert runs in its own transaction, since a failed statement aborts the transaction it runs in.
    @Test func compositePrimaryKeyActiveInsertRequiresAllKeys() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            var missingLine = ActiveModel<OrderLineModel>()
            missingLine.orderID = 1
            missingLine.note = "Missing line"
            await #expect(throws: (any Error).self) { try await missingLine.save(on: tx) }
        }
        try await withRollback { tx in
            try await setupSchema(on: tx)
            var missingOrder = ActiveModel<OrderLineModel>()
            missingOrder.lineID = 1
            missingOrder.note = "Missing order"
            await #expect(throws: (any Error).self) { try await missingOrder.save(on: tx) }
        }
    }

    @Test func activeDeleteRemovesOnlyTarget() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let user = try await seedUser(on: tx, name: "Delete", email: "delete@db.com")
            let other = try await seedUser(on: tx, name: "Keep", email: "keep@db.com")

            let deleted = try await user.active().delete(on: tx)
            #expect(deleted == 1)

            #expect(try await UserModel.find(user.id, on: tx) == nil)
            #expect(try await UserModel.find(other.id, on: tx)?.email == "keep@db.com")
        }
    }

    @Test func activeDeleteRequiresPrimaryKey() async {
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var active = ActiveModel<UserModel>()
                active.name = "No PK"
                active.email = "no-pk@db.com"
                _ = try await active.delete(on: tx)
            }
        }
    }

    @Test func compositePrimaryKeyActiveDeleteUsesBothKeys() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let target = try await seedOrderLine(on: tx, 1, 1, note: "A")
            _ = try await seedOrderLine(on: tx, 1, 2, note: "B")
            _ = try await seedOrderLine(on: tx, 2, 1, note: "C")

            let deleted = try await target.active().delete(on: tx)
            #expect(deleted == 1)

            #expect(try await orderLine(1, 1, on: tx) == nil)
            #expect(try await orderLine(1, 2, on: tx)?.note == "B")
            #expect(try await orderLine(2, 1, on: tx)?.note == "C")
        }
    }

    @Test func compositePrimaryKeyActiveDeleteRequiresAllKeys() async {
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var missingLine = ActiveModel<OrderLineModel>()
                missingLine.orderID = 1
                missingLine.note = "Missing line"
                _ = try await missingLine.delete(on: tx)
            }
        }
        await #expect(processExitsWith: .failure) {
            try await withRollback { tx in
                try await setupSchema(on: tx)
                var missingOrder = ActiveModel<OrderLineModel>()
                missingOrder.lineID = 1
                missingOrder.note = "Missing order"
                _ = try await missingOrder.delete(on: tx)
            }
        }
    }

    @Test func compositePrimaryKeyModelDeleteRemovesRow() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let target = try await seedOrderLine(on: tx, 9, 9, note: "Z")

            let deleted = try await target.delete(on: tx)
            #expect(deleted == 1)

            #expect(try await orderLine(target.orderID, target.lineID, on: tx) == nil)
        }
    }

    /// `Date` stands in for the `timestamp` and `date` values; rust-dbkit's `time` column has no Swift type.
    @Test func uuidDateTimeRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let day = isoDate("2024-01-02T00:00:00Z")
            let startsAt = isoDate("2024-01-02T03:04:05Z")
            let id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

            let inserted = try #require(
                try await EventModel.insert(EventModel.Insert(id: id, name: "Launch", startsAt: startsAt, day: day)).returningAll().first(
                    on: tx))
            #expect(inserted.id == id)
            #expect(inserted.startsAt == startsAt)
            #expect(inserted.day == day)

            let found = try #require(
                try await EventModel.query()
                    .filter(EventModel.id == id)
                    .filter(EventModel.day == day)
                    .filter(EventModel.startsAt == startsAt)
                    .first(on: tx))
            #expect(found.id == id)
            #expect(found.name == "Launch")
            #expect(found.startsAt == startsAt)
            #expect(found.day == day)
        }
    }

    @Test func arrayColumnRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let tags = ["alpha", "beta"]
            let inserted = try #require(try await ProfileModel.insert(ProfileModel.Insert(tags: tags)).returningAll().first(on: tx))
            #expect(inserted.tags == tags)

            let matched = try await ProfileModel.query().filter(ProfileModel.tags == tags).all(on: tx)
            #expect(matched.map(\.id) == [inserted.id])

            let updatedTags = ["gamma", "delta"]
            var active = inserted.active()
            active.tags = updatedTags
            let updated = try await active.update(on: tx)
            #expect(updated.tags == updatedTags)

            let fetched = try #require(try await ProfileModel.find(updated.id, on: tx))
            #expect(fetched.tags == updatedTags)
        }
    }

    @Test func jsonColumnRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let payload = JSONPayload(name: "alpha", active: true)
            let inserted = try #require(try await JSONRowModel.insert(JSONRowModel.Insert(data: payload)).returningAll().first(on: tx))
            #expect(inserted.data == payload)

            let matched = try await JSONRowModel.query().filter(JSONRowModel.data == payload).all(on: tx)
            #expect(matched.map(\.id) == [inserted.id])

            let updatedPayload = JSONPayload(name: "beta", active: false)
            var active = inserted.active()
            active.data = updatedPayload
            let updated = try await active.update(on: tx)
            #expect(updated.data == updatedPayload)

            let fetched = try #require(try await JSONRowModel.find(updated.id, on: tx))
            #expect(fetched.data == updatedPayload)
        }
    }

    /// rust-dbkit's borrowed values are plain `String?` constants here; Swift doesn't distinguish owned and borrowed.
    @Test func insertUpdateAndFilterNulls() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let inserted = try await seedNullableRow(on: tx, note: nil)
            #expect(inserted.note == nil)

            let someRow = try await seedNullableRow(on: tx, note: "hello")
            #expect(someRow.note == "hello")

            func setNote(_ note: String?) async throws -> [NullableRowModel] {
                try await NullableRowModel.update()
                    .set(NullableRowModel.note, to: note)
                    .filter(NullableRowModel.id == someRow.id)
                    .returningAll()
                    .all(on: tx)
            }

            var updated = try await NullableRowModel.update()
                .set(NullableRowModel.note, to: "direct")
                .filter(NullableRowModel.id == someRow.id)
                .returningAll()
                .all(on: tx)
            #expect(updated.first?.note == "direct")

            let optional: String? = "optional"
            updated = try await setNote(optional)
            #expect(updated.first?.note == "optional")

            let directMatch = try #require(try await NullableRowModel.query().filter(NullableRowModel.note == "optional").first(on: tx))
            #expect(directMatch.id == someRow.id)

            let optionalMatch = try #require(try await NullableRowModel.query().filter(NullableRowModel.note == optional).first(on: tx))
            #expect(optionalMatch.id == someRow.id)

            let borrowedOptional: String? = "borrowed"
            updated = try await setNote(borrowedOptional)
            #expect(updated.first?.note == "borrowed")

            let borrowedMatch = try #require(
                try await NullableRowModel.query().filter(NullableRowModel.note == borrowedOptional).first(on: tx))
            #expect(borrowedMatch.id == someRow.id)

            let borrowedNone: String? = nil
            updated = try await setNote(borrowedNone)
            #expect(updated.first?.note == nil)

            let borrowedNullMatch = try await NullableRowModel.query().filter(NullableRowModel.note == borrowedNone).all(on: tx)
            #expect(borrowedNullMatch.count == 2)

            updated = try await NullableRowModel.update()
                .set(NullableRowModel.note, to: nil)
                .filter(NullableRowModel.id == someRow.id)
                .returningAll()
                .all(on: tx)
            #expect(updated.count == 1)
            #expect(updated.first?.note == nil)

            let nullRows = try await NullableRowModel.query().filter(NullableRowModel.note == nil).all(on: tx)
            #expect(nullRows.count == 2)
            #expect(nullRows.allSatisfy { $0.note == nil })
        }
    }

    /// Rows decode into a `Decodable` struct by alias; rust-dbkit selects `note` without an alias, which `select` can't
    /// mix with aliased expressions, so it is aliased `note`.
    @Test func nullableValueComparisonProjectionsFollowPostgresThreeValuedLogic() async throws {
        struct ComparisonRow: Decodable {
            let note: String?
            let equalsDirect: Bool?
            let equalsOptional: Bool?
            let equalsNull: Bool?
            let differsDirect: Bool?
            let differsNull: Bool?
            let less: Bool?
            let lessOrEqual: Bool?
            let greater: Bool?
            let greaterOrEqual: Bool?
            let between: Bool?
            let matches: Bool?
            let matchesCaseInsensitively: Bool?
            let listed: Bool?
            let optionalList: Bool?
            let emptyList: Bool?
            let isNull: Bool
        }

        try await withRollback { tx in
            try await setupSchema(on: tx)
            for note in [nil, "alpha", "middle", "zulu"] {
                _ = try await seedNullableRow(on: tx, note: note)
            }

            let middle: String? = "middle"
            let rows = try await NullableRowModel.query()
                .select(
                    NullableRowModel.note.as("note"),
                    (NullableRowModel.note == "middle").as("equals_direct"),
                    (NullableRowModel.note == middle).as("equals_optional"),
                    (NullableRowModel.note == nil).as("equals_null"),
                    (NullableRowModel.note != "middle").as("differs_direct"),
                    (NullableRowModel.note != nil).as("differs_null"),
                    (NullableRowModel.note < "middle").as("less"),
                    (NullableRowModel.note <= "middle").as("less_or_equal"),
                    (NullableRowModel.note > "middle").as("greater"),
                    (NullableRowModel.note >= "middle").as("greater_or_equal"),
                    NullableRowModel.note.between("b", "y").as("between"),
                    NullableRowModel.note.like("m%").as("matches"),
                    NullableRowModel.note.ilike("M%").as("matches_case_insensitively"),
                    NullableRowModel.note.in(["alpha", "middle"]).as("listed"),
                    NullableRowModel.note.in(["alpha", nil]).as("optional_list"),
                    NullableRowModel.note.in([]).as("empty_list"),
                    NullableRowModel.note.isNull.as("is_null")
                )
                .orderBy(NullableRowModel.id.asc)
                .all(as: ComparisonRow.self, on: tx)

            #expect(rows.map(\.note) == [nil, "alpha", "middle", "zulu"])
            #expect(rows.map(\.equalsDirect) == [nil, false, true, false])
            #expect(rows.map(\.equalsOptional) == [nil, false, true, false])
            #expect(rows.map(\.equalsNull) == [true, false, false, false])
            #expect(rows.map(\.differsDirect) == [nil, true, false, true])
            #expect(rows.map(\.differsNull) == [false, true, true, true])

            #expect(rows.map(\.less) == [nil, true, false, false])
            #expect(rows.map(\.lessOrEqual) == [nil, true, true, false])
            #expect(rows.map(\.greater) == [nil, false, false, true])
            #expect(rows.map(\.greaterOrEqual) == [nil, false, true, true])
            #expect(rows.map(\.between) == [nil, false, true, false])

            #expect(rows.map(\.matches) == [nil, false, true, false])
            #expect(rows.map(\.matchesCaseInsensitively) == [nil, false, true, false])
            #expect(rows.map(\.listed) == [nil, true, true, false])
            #expect(rows.map(\.optionalList) == [nil, true, nil, nil])
            #expect(rows.map(\.emptyList) == [false, false, false, false])
            #expect(rows.map(\.isNull) == [true, false, false, false])

            let matching = try await NullableRowModel.query().filter(NullableRowModel.note == "middle").all(on: tx)
            #expect(matching.map(\.note) == ["middle"])
        }
    }

    /// The row `(null.id, NULL)` compares as NULL, never as a match.
    @Test func nullableRowValueInFollowsPostgresThreeValuedLogic() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let null = try await seedNullableRow(on: tx, note: nil)
            let alpha = try await seedNullableRow(on: tx, note: "alpha")
            let beta = try await seedNullableRow(on: tx, note: "beta")

            let alphaNote: String? = "alpha"
            let listed: Expr<Bool?> = SQL.row(NullableRowModel.id, NullableRowModel.note).in([(alpha.id, alphaNote), (null.id, nil)])
            // rust-dbkit decodes the projection into a struct; here it is a tuple.
            let rows: [(Int64, Bool?)] = try await NullableRowModel.query()
                .select(NullableRowModel.id, listed)
                .orderBy(NullableRowModel.id.asc)
                .all(on: tx)
            #expect(rows.map(\.0) == [null.id, alpha.id, beta.id])
            #expect(rows.map(\.1) == [nil, true, false])

            let filtered = try await NullableRowModel.query().filter(listed).all(on: tx)
            #expect(filtered.map(\.id) == [alpha.id])
        }
    }

    @Test func conditionsPreservePostgresThreeValuedLogic() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            for note in [nil, "alpha", "middle", "zulu"] {
                _ = try await seedNullableRow(on: tx, note: note)
            }

            func predicate(_ condition: Condition, _ build: (inout Condition) -> Void) throws -> Expr<Bool?> {
                var condition = condition
                build(&condition)
                return try #require(condition.predicate)
            }
            let singleNullable = try predicate(.all) { $0.add(NullableRowModel.note == "middle") }
            let allWithTrue = try predicate(.all) {
                $0.add(NullableRowModel.note == "middle")
                $0.add(NullableRowModel.id > 0)
            }
            let allWithFalse = try predicate(.all) {
                $0.add(NullableRowModel.note == "middle")
                $0.add(NullableRowModel.id < 0)
            }
            let anyWithFalse = try predicate(.any) {
                $0.add(NullableRowModel.id < 0)
                $0.add(NullableRowModel.note == "middle")
            }
            let anyWithTrue = try predicate(.any) {
                $0.add(NullableRowModel.id > 0)
                $0.add(NullableRowModel.note == "middle")
            }
            let requiredOnly = try predicate(.all) {
                $0.add(NullableRowModel.id > 0)
                $0.add(NullableRowModel.note.isNotNull)
            }
            // rust-dbkit decodes the projection into a struct; here it is a tuple. A predicate is always `Bool?` here,
            // see "A condition's predicate" in `docs/rust-parity.md`, so `required_only` decodes as `Bool?` where
            // rust-dbkit decodes `bool`.
            let rows: [(String?, Bool?, Bool?, Bool?, Bool?, Bool?, Bool?)] = try await NullableRowModel.query()
                .select(NullableRowModel.note, singleNullable, allWithTrue, allWithFalse, anyWithFalse, anyWithTrue, requiredOnly)
                .orderBy(NullableRowModel.id.asc)
                .all(on: tx)

            #expect(rows.map(\.0) == [nil, "alpha", "middle", "zulu"])
            #expect(rows.map(\.1) == [nil, false, true, false])  // single_nullable
            #expect(rows.map(\.2) == [nil, false, true, false])  // all_with_true
            #expect(rows.map(\.3) == [false, false, false, false])  // all_with_false
            #expect(rows.map(\.4) == [nil, false, true, false])  // any_with_false
            #expect(rows.map(\.5) == [true, true, true, true])  // any_with_true
            #expect(rows.map(\.6) == [false, true, true, true])  // required_only

            var condition = Condition.all
            condition.add(NullableRowModel.note == "middle")
            condition.add(NullableRowModel.id > 0)
            let matching = try await NullableRowModel.query().filter(try #require(condition.predicate)).all(on: tx)
            #expect(matching.count == 1)
            #expect(matching.first?.note == "middle")
        }
    }
}

/// rust-dbkit's `setup_schema`, with the temp tables of the tests ported so far.
private func setupSchema(on tx: Transaction) async throws {
    try await tx.query("CREATE TEMP TABLE users (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL, region TEXT)")
    try await tx.query("CREATE TEMP TABLE nullable_rows (id BIGSERIAL PRIMARY KEY, note TEXT NULL)")
    try await tx.query(
        "CREATE TEMP TABLE order_lines (order_id BIGINT NOT NULL, line_id BIGINT NOT NULL, note TEXT NOT NULL, PRIMARY KEY (order_id, line_id))"
    )
    try await tx.query(
        """
        CREATE TEMP TABLE run_payloads (
            target_id BIGINT NOT NULL, run_id BIGINT NOT NULL, payload TEXT NOT NULL, source TEXT NOT NULL, version BIGINT NOT NULL,
            PRIMARY KEY (target_id, run_id)
        )
        """)
    try await tx.query("CREATE TEMP TABLE profiles (id BIGSERIAL PRIMARY KEY, tags TEXT[] NOT NULL)")
    try await tx.query("CREATE TEMP TABLE json_rows (id BIGSERIAL PRIMARY KEY, data JSONB NOT NULL)")
    try await tx.query(
        "CREATE TEMP TABLE events (id UUID PRIMARY KEY, name TEXT NOT NULL, starts_at TIMESTAMP NOT NULL, day DATE NOT NULL)")
}

private func seedUser(on tx: Transaction, name: String, email: String) async throws -> UserModel {
    try #require(try await UserModel.insert(UserModel.Insert(name: name, email: email)).returningAll().first(on: tx))
}

private func seedNullableRow(on tx: Transaction, note: String?) async throws -> NullableRowModel {
    try #require(try await NullableRowModel.insert(NullableRowModel.Insert(note: note)).returningAll().first(on: tx))
}

private func seedOrderLine(on tx: Transaction, _ orderID: Int64, _ lineID: Int64, note: String) async throws -> OrderLineModel {
    try #require(
        try await OrderLineModel.insert(OrderLineModel.Insert(orderID: orderID, lineID: lineID, note: note)).returningAll().first(on: tx))
}

private func seedRunPayload(
    on tx: Transaction, _ targetID: Int64, _ runID: Int64, payload: String, source: String, version: Int64
) async throws -> RunPayloadModel {
    try #require(
        try await RunPayloadModel.insert(
            RunPayloadModel.Insert(targetID: targetID, runID: runID, payload: payload, source: source, version: version)
        )
        .returningAll().first(on: tx))
}

private func runPayloads(_ targetID: Int64, _ runID: Int64, on tx: Transaction) async throws -> [RunPayloadModel] {
    try await RunPayloadModel.query().filter(RunPayloadModel.targetID == targetID).filter(RunPayloadModel.runID == runID).all(on: tx)
}

private func orderLine(_ orderID: Int64, _ lineID: Int64, on tx: Transaction) async throws -> OrderLineModel? {
    try await OrderLineModel.query().filter(OrderLineModel.orderID == orderID).filter(OrderLineModel.lineID == lineID).first(on: tx)
}
