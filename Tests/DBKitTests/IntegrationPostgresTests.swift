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
}

/// rust-dbkit's `setup_schema`, with the temp tables of the tests ported so far.
private func setupSchema(on tx: Transaction) async throws {
    try await tx.query("CREATE TEMP TABLE users (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL, region TEXT)")
}

private func seedUser(on tx: Transaction, name: String, email: String) async throws -> UserModel {
    try #require(try await UserModel.insert(UserModel.Insert(name: name, email: email)).returningAll().first(on: tx))
}
