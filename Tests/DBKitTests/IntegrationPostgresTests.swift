import DBKit
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
}

/// rust-dbkit's `setup_schema`, with the temp tables of the tests ported so far.
private func setupSchema(on tx: Transaction) async throws {
    try await tx.query("CREATE TEMP TABLE users (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL, region TEXT)")
    try await tx.query("CREATE TEMP TABLE nullable_rows (id BIGSERIAL PRIMARY KEY, note TEXT NULL)")
    try await tx.query(
        "CREATE TEMP TABLE order_lines (order_id BIGINT NOT NULL, line_id BIGINT NOT NULL, note TEXT NOT NULL, PRIMARY KEY (order_id, line_id))"
    )
}

private func seedUser(on tx: Transaction, name: String, email: String) async throws -> UserModel {
    try #require(try await UserModel.insert(UserModel.Insert(name: name, email: email)).returningAll().first(on: tx))
}

private func seedOrderLine(on tx: Transaction, _ orderID: Int64, _ lineID: Int64, note: String) async throws -> OrderLineModel {
    try #require(
        try await OrderLineModel.insert(OrderLineModel.Insert(orderID: orderID, lineID: lineID, note: note)).returningAll().first(on: tx))
}

private func orderLine(_ orderID: Int64, _ lineID: Int64, on tx: Transaction) async throws -> OrderLineModel? {
    try await OrderLineModel.query().filter(OrderLineModel.orderID == orderID).filter(OrderLineModel.lineID == lineID).first(on: tx)
}
