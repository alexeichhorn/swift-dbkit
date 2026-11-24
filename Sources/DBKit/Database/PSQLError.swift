import PostgresNIO

extension PSQLError {
    /// The constraint the server reported as violated, if any.
    public var constraintName: String? {
        serverInfo?[.constraintName]
    }

    /// Whether the error is a unique violation (SQLSTATE 23505), and of `constraint` when one is given:
    /// `catch let error as PSQLError where error.isUniqueViolation(of: "users_email_key")`.
    public func isUniqueViolation(of constraint: String? = nil) -> Bool {
        serverInfo?[.sqlState] == PostgresError.Code.uniqueViolation.raw && (constraint == nil || constraintName == constraint)
    }
}
