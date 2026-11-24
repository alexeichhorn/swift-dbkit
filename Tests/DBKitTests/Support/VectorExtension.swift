import DBKit

/// Creates pgvector's `vector` extension on the test database, once per test run and committed. A vector test calls
/// it before `withRollback`: creating the extension inside each test's transaction would make parallel tests wait on
/// each other.
func ensureVectorExtension() async throws {
    try await vectorExtension.value
}

private let vectorExtension = Task {
    _ = try await testDatabase().query("CREATE EXTENSION IF NOT EXISTS vector")
}
