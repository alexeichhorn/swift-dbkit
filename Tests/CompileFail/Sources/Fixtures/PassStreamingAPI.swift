import DBKit

// rust-dbkit's `pass_streaming_api.rs`. A stream takes a query and its bound values that may be temporaries, and it is
// `Sendable`, as rust-dbkit's is `Send`.

private func requireSendable<Rows: AsyncSequence & Sendable>(_ rows: Rows, of element: Rows.Element.Type) {}

private func streamOnADatabase(_ db: Database) async throws {
    let rows = try await {
        let label = String("first")
        return try await PathRecordModel.query().filter(PathRecordModel.label == label).stream(on: db)
    }()
    for try await record in rows {
        let _: PathRecordModel = record
    }

    let records = try await PathRecordModel.query().stream(on: db)
    requireSendable(records, of: PathRecordModel.self)
    let labels = try await PathRecordModel.query()
        .select(PathRecordModel.id, PathRecordModel.Relations.owner.label)
        .orderBy(PathRecordModel.id.asc)
        .stream(on: db)
    requireSendable(labels, of: (Int64, String?).self)
}

private func streamInATransaction(_ tx: Transaction) async throws {
    let skippingLocked = try await PathRecordModel.query().forUpdate(.skipLocked).stream(on: tx)
    requireSendable(skippingLocked, of: PathRecordModel.self)
    let failingOnLocks = try await PathRecordModel.query().forUpdate(.noWait).stream(on: tx)
    requireSendable(failingOnLocks, of: PathRecordModel.self)
    for try await record in try await PathRecordModel.query().stream(on: tx) {
        let _: PathRecordModel = record
    }
}
