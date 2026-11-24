import DBKit
import Testing

@Model(table: "accounts_exists")
class AccountExistsModel {
    @Key @AutoIncrement var id: Int64
    var name: String
    var tier: String
}

@Model(table: "subscriptions_exists")
class SubscriptionExistsModel {
    @Key @AutoIncrement var id: Int64
    var accountID: Int64
    var category: String
    var state: String
}

@Suite struct IntegrationExistsSubqueryTests {
    @Test func whereExistsReturnsRowsWithMatchingChildren() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let atlas = try await seedAccount(on: tx, "Atlas", "pro")
            let birch = try await seedAccount(on: tx, "Birch", "pro")
            let cinder = try await seedAccount(on: tx, "Cinder", "free")
            try await seedSubscriptions(
                on: tx, [(atlas.id, "alerts", "enabled"), (birch.id, "alerts", "disabled"), (cinder.id, "alerts", "enabled")])

            let rows = try await AccountExistsModel.query()
                .filter(AccountExistsModel.tier == "pro")
                .whereExists(enabledAlerts(of: AccountExistsModel.id))
                .orderBy(AccountExistsModel.id.asc)
                .all(on: tx)

            #expect(rows.map(\.name) == ["Atlas"])
        }
    }

    @Test func whereNotExistsReturnsRowsWithoutMatchingChildren() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let atlas = try await seedAccount(on: tx, "Atlas", "pro")
            let birch = try await seedAccount(on: tx, "Birch", "pro")
            _ = try await seedAccount(on: tx, "Cinder", "pro")
            try await seedSubscriptions(on: tx, [(atlas.id, "alerts", "enabled"), (birch.id, "reports", "enabled")])

            let rows = try await AccountExistsModel.query()
                .filter(AccountExistsModel.tier == "pro")
                .whereNotExists(enabledAlerts(of: AccountExistsModel.id))
                .orderBy(AccountExistsModel.id.asc)
                .all(on: tx)

            #expect(rows.map(\.name) == ["Birch", "Cinder"])
        }
    }

    @Test func deleteWhereExistsRemovesRowsWithMatchingParent() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let atlas = try await seedAccount(on: tx, "Atlas", "free")
            let birch = try await seedAccount(on: tx, "Birch", "pro")
            try await seedSubscriptions(
                on: tx, [(atlas.id, "alerts", "enabled"), (birch.id, "alerts", "enabled"), (birch.id, "reports", "disabled")])

            let deleted = try await SubscriptionExistsModel.delete()
                .whereExists(freeAccount(of: SubscriptionExistsModel.accountID))
                .execute(on: tx)

            #expect(deleted == 1)
            let remaining = try await SubscriptionExistsModel.query().orderBy(SubscriptionExistsModel.id.asc).all(on: tx)
            #expect(remaining.map(\.accountID) == [birch.id, birch.id])
        }
    }

    @Test func deleteWhereNotExistsRemovesRowsWithoutMatchingChildren() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let atlas = try await seedAccount(on: tx, "Atlas", "pro")
            let birch = try await seedAccount(on: tx, "Birch", "pro")
            _ = try await seedAccount(on: tx, "Cinder", "free")
            try await seedSubscriptions(on: tx, [(atlas.id, "alerts", "enabled"), (birch.id, "reports", "enabled")])

            let deleted = try await AccountExistsModel.delete()
                .filter(AccountExistsModel.tier == "pro")
                .whereNotExists(enabledAlerts(of: AccountExistsModel.id))
                .execute(on: tx)

            #expect(deleted == 1)
            let remaining = try await AccountExistsModel.query().orderBy(AccountExistsModel.id.asc).all(on: tx)
            #expect(remaining.map(\.name) == ["Atlas", "Cinder"])
        }
    }

    @Test func updateWhereExistsMutatesRowsWithMatchingParent() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let atlas = try await seedAccount(on: tx, "Atlas", "free")
            let birch = try await seedAccount(on: tx, "Birch", "pro")
            try await seedSubscriptions(on: tx, [(atlas.id, "alerts", "enabled"), (birch.id, "alerts", "enabled")])

            let updated = try await SubscriptionExistsModel.update()
                .set(SubscriptionExistsModel.state, to: "retired")
                .whereExists(freeAccount(of: SubscriptionExistsModel.accountID))
                .returningAll()
                .all(on: tx)

            #expect(updated.map(\.accountID) == [atlas.id])
            #expect(updated.map(\.state) == ["retired"])
            let rows = try await SubscriptionExistsModel.query().orderBy(SubscriptionExistsModel.id.asc).all(on: tx)
            #expect(rows.map(\.state) == ["retired", "enabled"])
        }
    }

    @Test func updateWhereNotExistsMutatesRowsWithoutMatchingChildren() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let atlas = try await seedAccount(on: tx, "Atlas", "pro")
            let birch = try await seedAccount(on: tx, "Birch", "pro")
            _ = try await seedAccount(on: tx, "Cinder", "free")
            try await seedSubscriptions(on: tx, [(atlas.id, "alerts", "enabled"), (birch.id, "reports", "enabled")])

            let updated = try await AccountExistsModel.update()
                .set(AccountExistsModel.tier, to: "dormant")
                .filter(AccountExistsModel.tier == "pro")
                .whereNotExists(enabledAlerts(of: AccountExistsModel.id))
                .returningAll()
                .all(on: tx)

            #expect(updated.map(\.name) == ["Birch"])
            #expect(updated.map(\.tier) == ["dormant"])
            let rows = try await AccountExistsModel.query().orderBy(AccountExistsModel.id.asc).all(on: tx)
            #expect(rows.map(\.tier) == ["pro", "dormant", "free"])
        }
    }

    // Waits for slice 22: `whereExistsPreservesSkipLockedSubquerySemantics`, an `EXISTS` subquery with
    // `forUpdate(.skipLocked)` that skips a row another connection locked.
}

/// The enabled `alerts` subscriptions of the account whose id is `accountID`, usually a column of the outer query.
private func enabledAlerts(of accountID: Column<AccountExistsModel, Int64>) -> Projection<Int64> {
    SubscriptionExistsModel.query()
        .select(SubscriptionExistsModel.id)
        .filter(SubscriptionExistsModel.accountID == accountID)
        .filter(SubscriptionExistsModel.category == "alerts")
        .filter(SubscriptionExistsModel.state == "enabled")
}

/// The `free` account whose id is `accountID`, usually a column of the outer query.
private func freeAccount(of accountID: Column<SubscriptionExistsModel, Int64>) -> Projection<Int64> {
    AccountExistsModel.query()
        .select(AccountExistsModel.id)
        .filter(AccountExistsModel.id == accountID)
        .filter(AccountExistsModel.tier == "free")
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query("CREATE TEMP TABLE accounts_exists (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, tier TEXT NOT NULL)")
    try await tx.query(
        """
        CREATE TEMP TABLE subscriptions_exists (
            id BIGSERIAL PRIMARY KEY, account_id BIGINT NOT NULL, category TEXT NOT NULL, state TEXT NOT NULL
        )
        """)
}

private func seedAccount(on tx: Transaction, _ name: String, _ tier: String) async throws -> AccountExistsModel {
    try #require(try await AccountExistsModel.insert(AccountExistsModel.Insert(name: name, tier: tier)).returningAll().first(on: tx))
}

private func seedSubscriptions(on tx: Transaction, _ rows: [(accountID: Int64, category: String, state: String)]) async throws {
    let inserts = rows.map { SubscriptionExistsModel.Insert(accountID: $0.accountID, category: $0.category, state: $0.state) }
    _ = try await SubscriptionExistsModel.insert(inserts).execute(on: tx)
}
