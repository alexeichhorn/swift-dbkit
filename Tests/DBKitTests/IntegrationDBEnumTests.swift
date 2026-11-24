import DBKit
import Testing

@DatabaseEnum("run_state")
enum RunState { case scheduled, running, succeeded, failed }

@DatabaseEnum("run_outcome")
enum RunOutcome { case ok, error, timeout }

@DatabaseEnum("pg_temp.qualified_run_state")
enum QualifiedRunState { case scheduled, running, completed }

@Model(table: "workflow_runs")
class WorkflowRunModel {
    @Key @AutoIncrement var id: Int64
    var externalRef: String
    var payload: String
    var state: RunState
    var outcome: RunOutcome?
    var attempts: Int64
}

/// Its enum is `IntegrationMode` of `EnumSQLSupportTests.swift`.
@Model(table: "integration_events")
class IntegrationEventModel {
    @Key @AutoIncrement var id: Int64
    var extID: String
    var mode: IntegrationMode
    var fallbackMode: IntegrationMode?
}

@Model(table: "workflow_groups")
class WorkflowGroupModel {
    @Key @AutoIncrement var id: Int64
    var name: String
}

@Model(table: "workflow_group_runs")
class WorkflowGroupRunModel {
    @Key @AutoIncrement var id: Int64
    var groupID: Int64
    var state: QualifiedRunState
}

/// The enum types are created in `pg_temp`, which PostgreSQL searches for types before any other schema, so they
/// vanish with the transaction like the tables.
@Suite struct IntegrationDBEnumTests {
    @Test func enumRoundtripFilterUpdateAndOptionalNulling() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)

            let inserted = try await seedRun(on: tx, "run-1", "payload-v1", .scheduled, nil, 0)
            #expect(inserted.state == .scheduled)
            #expect(inserted.outcome == nil)

            let byState = try #require(try await WorkflowRunModel.query().filter(WorkflowRunModel.state == .scheduled).first(on: tx))
            #expect(byState.id == inserted.id)
            #expect(byState.externalRef == "run-1")

            let updatedRows = try await WorkflowRunModel.update()
                .set(WorkflowRunModel.state, to: .running)
                .set(WorkflowRunModel.outcome, to: .ok)
                .set(WorkflowRunModel.attempts, to: 1)
                .filter(WorkflowRunModel.id == inserted.id)
                .returningAll()
                .all(on: tx)
            #expect(updatedRows.count == 1)
            let updated = try #require(updatedRows.first)
            #expect(updated.state == .running)
            #expect(updated.outcome == .ok)
            #expect(updated.attempts == 1)

            var active = updated.active()
            active.state = .succeeded
            active.outcome = nil
            let finished = try await active.update(on: tx)
            #expect(finished.state == .succeeded)
            #expect(finished.outcome == nil)

            let done = try await WorkflowRunModel.query().filter(WorkflowRunModel.state.in([.running, .succeeded])).all(on: tx)
            #expect(done.count == 1)
            #expect(done.first?.externalRef == "run-1")
            #expect(done.first?.state == .succeeded)

            let withoutOutcome = try await WorkflowRunModel.query().filter(WorkflowRunModel.outcome == nil).all(on: tx)
            #expect(withoutOutcome.map(\.id) == [inserted.id])
        }
    }

    @Test func enumUpsertUpdatesSelectedEnumColumnsAndPreservesUnselectedFields() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let original = try await seedRun(on: tx, "same-ref", "payload-original", .scheduled, nil, 0)

            let upserted = try #require(
                try await WorkflowRunModel.insert(
                    WorkflowRunModel.Insert(
                        externalRef: "same-ref", payload: "payload-new-but-should-not-overwrite", state: .failed, outcome: .timeout,
                        attempts: 5)
                )
                .onConflict(
                    WorkflowRunModel.externalRef, doUpdate: WorkflowRunModel.state, WorkflowRunModel.outcome, WorkflowRunModel.attempts
                )
                .returningAll()
                .first(on: tx))
            #expect(upserted.id == original.id)
            #expect(upserted.externalRef == "same-ref")
            #expect(upserted.payload == "payload-original")
            #expect(upserted.state == .failed)
            #expect(upserted.outcome == .timeout)
            #expect(upserted.attempts == 5)

            let fetched = try #require(try await WorkflowRunModel.query().filter(WorkflowRunModel.externalRef == "same-ref").first(on: tx))
            #expect(fetched.id == original.id)
            #expect(fetched.payload == "payload-original")
            #expect(fetched.state == .failed)
            #expect(fetched.outcome == .timeout)
            #expect(fetched.attempts == 5)
        }
    }

    @Test func whereExistsWorksWithSchemaQualifiedEnumCasts() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let alpha = try await seedGroup(on: tx, "alpha")
            _ = try await seedGroup(on: tx, "beta")
            try await WorkflowGroupRunModel.insert([
                WorkflowGroupRunModel.Insert(groupID: alpha.id, state: .running),
                WorkflowGroupRunModel.Insert(groupID: alpha.id, state: .completed),
                WorkflowGroupRunModel.Insert(groupID: alpha.id + 1, state: .scheduled),
            ]).execute(on: tx)

            let rows = try await WorkflowGroupModel.query()
                .whereExists(
                    WorkflowGroupRunModel.query()
                        .select(WorkflowGroupRunModel.id)
                        .filter(WorkflowGroupRunModel.groupID == WorkflowGroupModel.id)
                        .filter(WorkflowGroupRunModel.state == .running)
                )
                .all(on: tx)

            #expect(rows.map(\.name) == ["alpha"])
        }
    }

    @Test func enumAcronymWireNamesRoundtripForCRUDFiltersAndUpsert() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)

            let inserted = try #require(
                try await IntegrationEventModel.insert(
                    IntegrationEventModel.Insert(extID: "evt-1", mode: .httpWebhook, fallbackMode: .oauthToken)
                )
                .returningAll()
                .first(on: tx))
            #expect(inserted.mode == .httpWebhook)
            #expect(inserted.fallbackMode == .oauthToken)

            let filtered = try #require(
                try await IntegrationEventModel.query()
                    .filter(IntegrationEventModel.mode == .httpWebhook)
                    .filter(IntegrationEventModel.fallbackMode.in([.oauthToken]))
                    .first(on: tx))
            #expect(filtered.id == inserted.id)

            let updatedRows = try await IntegrationEventModel.update()
                .set(IntegrationEventModel.mode, to: .webhookHTTP)
                .set(IntegrationEventModel.fallbackMode, to: nil)
                .filter(IntegrationEventModel.id == inserted.id)
                .returningAll()
                .all(on: tx)
            #expect(updatedRows.count == 1)
            let updated = try #require(updatedRows.first)
            #expect(updated.mode == .webhookHTTP)
            #expect(updated.fallbackMode == nil)

            let upserted = try #require(
                try await IntegrationEventModel.insert(
                    IntegrationEventModel.Insert(extID: "evt-1", mode: .xmlHttpRequest, fallbackMode: .httpWebhook)
                )
                .onConflict(IntegrationEventModel.extID, doUpdate: IntegrationEventModel.mode, IntegrationEventModel.fallbackMode)
                .returningAll()
                .first(on: tx))
            #expect(upserted.id == inserted.id)
            #expect(upserted.mode == .xmlHttpRequest)
            #expect(upserted.fallbackMode == .httpWebhook)
        }
    }
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query("CREATE TYPE pg_temp.run_state AS ENUM ('scheduled', 'running', 'succeeded', 'failed')")
    try await tx.query("CREATE TYPE pg_temp.run_outcome AS ENUM ('ok', 'error', 'timeout')")
    try await tx.query(
        """
        CREATE TEMP TABLE workflow_runs (
            id BIGSERIAL PRIMARY KEY, external_ref TEXT NOT NULL UNIQUE, payload TEXT NOT NULL, state run_state NOT NULL,
            outcome run_outcome NULL, attempts BIGINT NOT NULL
        )
        """)
    try await tx.query(
        "CREATE TYPE pg_temp.integration_mode AS ENUM ('http_webhook', 'oauth_token', 'xml_http_request', 'webhook_http', 'dns_probe')")
    try await tx.query("CREATE TYPE pg_temp.qualified_run_state AS ENUM ('scheduled', 'running', 'completed')")
    try await tx.query(
        """
        CREATE TEMP TABLE integration_events (
            id BIGSERIAL PRIMARY KEY, ext_id TEXT NOT NULL UNIQUE, mode integration_mode NOT NULL,
            fallback_mode integration_mode NULL
        )
        """)
    try await tx.query("CREATE TEMP TABLE workflow_groups (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL)")
    try await tx.query(
        "CREATE TEMP TABLE workflow_group_runs (id BIGSERIAL PRIMARY KEY, group_id BIGINT NOT NULL, state qualified_run_state NOT NULL)")
}

private func seedRun(
    on tx: Transaction, _ externalRef: String, _ payload: String, _ state: RunState, _ outcome: RunOutcome?, _ attempts: Int64
) async throws -> WorkflowRunModel {
    try #require(
        try await WorkflowRunModel.insert(
            WorkflowRunModel.Insert(externalRef: externalRef, payload: payload, state: state, outcome: outcome, attempts: attempts)
        )
        .returningAll().first(on: tx))
}

private func seedGroup(on tx: Transaction, _ name: String) async throws -> WorkflowGroupModel {
    try #require(try await WorkflowGroupModel.insert(WorkflowGroupModel.Insert(name: name)).returningAll().first(on: tx))
}
