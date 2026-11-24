/// A model being edited, tracking which columns you set so updates write only those.
///
/// Get one from a loaded row with `row.active()`, or start a new row with `ActiveModel<UserModel>()`:
///
/// ```swift
/// var active = user.active()
/// active.name = "Renamed"
/// let updated = try await active.update(on: db)   // UPDATE users SET name = $1 WHERE id = $2 RETURNING *
/// ```
@dynamicMemberLookup
public struct ActiveModel<M: Model>: Sendable where M.Base == M {
    private let original: M?
    private var changes: [String: any SQLType] = [:]

    /// A new row; `save(on:)` inserts it.
    public init() {
        original = nil
    }

    init(_ row: M) {
        original = row
    }

    /// Reads the set value, or the loaded value. Reading an unset column of a new row is a programmer error.
    public subscript<V: SQLType>(dynamicMember keyPath: KeyPath<M, V>) -> V {
        get {
            if let value = changes[Self.column(keyPath)] { return value as! V }
            guard let original else { preconditionFailure("\(Self.column(keyPath)) is not set on this new \(M.self)") }
            return original[keyPath: keyPath]
        }
        set { changes[Self.column(keyPath)] = newValue }
    }

    /// Writes the set columns by primary key and returns the updated row. Returns the row unchanged without a query
    /// when nothing was set.
    public func update(on executor: some DatabaseExecutor) async throws -> M {
        guard let original else { preconditionFailure("update(on:) needs a loaded row; use save(on:) for new rows") }
        let assignments = changedValues
        guard !assignments.isEmpty else { return original }
        let query = UpdateQuery<M>(assignments: assignments).filtered(original.primaryKeyPredicate)
        guard let row = try await query.returningAll().first(on: executor) else { throw DBKitError.rowNotFound }
        return row
    }

    /// Inserts a new row with the set columns, or updates a loaded row.
    public func save(on executor: some DatabaseExecutor) async throws -> M {
        guard original == nil else { return try await update(on: executor) }
        guard let row = try await InsertQuery<M>(rows: [changedValues]).returningAll().first(on: executor) else {
            throw DBKitError.rowNotFound
        }
        return row
    }

    /// Deletes the loaded row by primary key.
    @discardableResult
    public func delete(on executor: some DatabaseExecutor) async throws -> Int {
        guard let original else { preconditionFailure("delete(on:) needs a loaded row") }
        return try await original.delete(on: executor)
    }

    private var changedValues: [ColumnValue] {
        M.schema.columns.compactMap { column in changes[column].map { ColumnValue(column: column, node: $0.sqlNode) } }
    }

    private static func column(_ keyPath: PartialKeyPath<M>) -> String {
        guard let column = M.columnName(for: keyPath) else { preconditionFailure("\(keyPath) is not a column of \(M.self)") }
        return column
    }
}
