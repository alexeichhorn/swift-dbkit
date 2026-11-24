import DBKit
import Testing

@DatabaseEnum("queue_state")
enum QueueState { case queued, running, completed, failed }

@DatabaseEnum("delivery_channel")
enum DeliveryChannel { case email, sms, webhook }

/// Its labels check how snake_case splits acronyms, with the case names Swift's naming rules give rust-dbkit's
/// variants. rust-dbkit renames `DNSProbe` to `dns_probe`, the label `dnsProbe` gets here without a rename.
@DatabaseEnum("integration_mode")
enum IntegrationMode { case httpWebhook, oauthToken, xmlHttpRequest, webhookHTTP, dnsProbe }

/// rust-dbkit's `QualifiedRunState` of this file.
@DatabaseEnum("app.run_state")
enum AppRunState { case scheduled, running, completed }

@Model(table: "message_jobs")
class MessageJobModel {
    @Key var id: Int64
    var dedupeKey: String
    var state: QueueState
    var channel: DeliveryChannel?
    var attempts: Int64
}

@Model(table: "integration_jobs")
class IntegrationJobModel {
    @Key var id: Int64
    var mode: IntegrationMode
}

@Model(table: "job_batches")
class JobBatchModel {
    @Key var id: Int64
    var label: String
}

@Model(table: "job_attempts")
class JobAttemptModel {
    @Key var id: Int64
    var batchID: Int64
    var state: AppRunState
}

/// This port binds a value each time it appears, where rust-dbkit binds identical values once and repeats their
/// placeholder. Both mean the same.
@Suite struct EnumSQLSupportTests {
    /// rust-dbkit renders the `IN` list as `($1::queue_state, $2::queue_state)`.
    @Test func enumFilterSQLUsesTypedCastsAndStableBindReuse() {
        let rendered = MessageJobModel.query()
            .filter(MessageJobModel.state == .queued)
            .filter(MessageJobModel.state.in([.queued, .running]))
            .filter(MessageJobModel.channel == .email)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "message_jobs".* FROM "message_jobs" WHERE "message_jobs"."state" = $1::queue_state AND "message_jobs"."state" IN ($2::queue_state, $3::queue_state) AND "message_jobs"."channel" = $4::delivery_channel"#
        )
        #expect(
            bindValues(rendered) == ["queue_state:queued", "queue_state:queued", "queue_state:running", "delivery_channel:email"])
    }

    @Test func enumNullPathsCompileWithoutTypedBindPlaceholders() {
        let select = MessageJobModel.query().filter(MessageJobModel.channel == nil).render()
        #expect(select.sql == #"SELECT "message_jobs".* FROM "message_jobs" WHERE "message_jobs"."channel" IS NULL"#)
        #expect(select.binds.isEmpty)

        let update = MessageJobModel.update().set(MessageJobModel.channel, to: nil).filter(MessageJobModel.id == 11).render()
        #expect(update.sql == #"UPDATE "message_jobs" SET "channel" = NULL WHERE "message_jobs"."id" = $1"#)
        #expect(bindValues(update) == ["11"])
    }

    @Test func enumUpdateAndInsertConflictSQLKeepExplicitTypeCasts() {
        let update = MessageJobModel.update()
            .set(MessageJobModel.state, to: .completed)
            .set(MessageJobModel.channel, to: .webhook)
            .set(MessageJobModel.attempts, to: 2)
            .filter(MessageJobModel.id == 42)
            .render()
        #expect(
            update.sql
                == #"UPDATE "message_jobs" SET "state" = $1::queue_state, "channel" = $2::delivery_channel, "attempts" = $3 WHERE "message_jobs"."id" = $4"#
        )
        #expect(bindValues(update) == ["queue_state:completed", "delivery_channel:webhook", "2", "42"])

        let insert = MessageJobModel.insert(
            MessageJobModel.Insert(id: 42, dedupeKey: "job-42", state: .queued, channel: .sms, attempts: 0)
        )
        .onConflict(MessageJobModel.dedupeKey, doUpdate: MessageJobModel.state, MessageJobModel.channel, MessageJobModel.attempts)
        .returningAll()
        .render()
        #expect(
            insert.sql
                == #"INSERT INTO "message_jobs" ("id", "dedupe_key", "state", "channel", "attempts") VALUES ($1, $2, $3::queue_state, $4::delivery_channel, $5) ON CONFLICT ("dedupe_key") DO UPDATE SET "state" = EXCLUDED."state", "channel" = EXCLUDED."channel", "attempts" = EXCLUDED."attempts" RETURNING *"#
        )
        #expect(bindValues(insert) == ["42", "job-42", "queue_state:queued", "delivery_channel:sms", "0"])
    }

    @Test func enumEmptyInCompilesToFalseWithoutBinds() {
        let rendered = MessageJobModel.query().filter(MessageJobModel.state.in([])).render()
        #expect(rendered.sql == #"SELECT "message_jobs".* FROM "message_jobs" WHERE FALSE"#)
        #expect(rendered.binds.isEmpty)
    }

    @Test func enumSnakeCaseHandlesAcronymsForValueAndFromStrPaths() {
        let labels: [(IntegrationMode, String)] = [
            (.httpWebhook, "http_webhook"),
            (.oauthToken, "oauth_token"),
            (.xmlHttpRequest, "xml_http_request"),
            (.webhookHTTP, "webhook_http"),
            (.dnsProbe, "dns_probe"),
        ]
        for (mode, label) in labels {
            #expect(mode.rawValue == label)
            #expect(IntegrationMode(rawValue: label) == mode)
        }

        #expect(IntegrationMode.typeName == "integration_mode")
        let bound = IntegrationJobModel.query().filter(IntegrationJobModel.mode == .httpWebhook).render()
        #expect(bindValues(bound) == ["integration_mode:http_webhook"])
    }

    @Test func enumSQLUsesExpectedAcronymWireValuesInFiltersAndUpdates() {
        let select = IntegrationJobModel.query()
            .filter(IntegrationJobModel.mode == .httpWebhook)
            .filter(IntegrationJobModel.mode.in([.oauthToken, .xmlHttpRequest]))
            .render()
        #expect(
            select.sql
                == #"SELECT "integration_jobs".* FROM "integration_jobs" WHERE "integration_jobs"."mode" = $1::integration_mode AND "integration_jobs"."mode" IN ($2::integration_mode, $3::integration_mode)"#
        )
        #expect(
            bindValues(select) == [
                "integration_mode:http_webhook", "integration_mode:oauth_token", "integration_mode:xml_http_request",
            ])

        let update = IntegrationJobModel.update()
            .set(IntegrationJobModel.mode, to: .webhookHTTP)
            .filter(IntegrationJobModel.id == 5)
            .render()
        #expect(update.sql == #"UPDATE "integration_jobs" SET "mode" = $1::integration_mode WHERE "integration_jobs"."id" = $2"#)
        #expect(bindValues(update) == ["integration_mode:webhook_http", "5"])
    }

    @Test func existsSubqueryRebindPreservesSchemaQualifiedEnumCasts() {
        let rendered = JobBatchModel.query()
            .whereExists(
                JobAttemptModel.query()
                    .select(JobAttemptModel.id)
                    .filter(JobAttemptModel.batchID == JobBatchModel.id)
                    .filter(JobAttemptModel.state == .running)
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "job_batches".* FROM "job_batches" WHERE EXISTS (SELECT "job_attempts"."id" FROM "job_attempts" WHERE "job_attempts"."batch_id" = "job_batches"."id" AND "job_attempts"."state" = $1::app.run_state)"#
        )
        #expect(bindValues(rendered) == ["app.run_state:running"])
    }
}
