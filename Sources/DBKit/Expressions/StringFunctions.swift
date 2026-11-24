// PostgreSQL string functions. The text argument decides nullability; the other arguments must be non-null
// (use `??` to supply a fallback), except a prefix, which makes the result nullable. Swift values become bind
// parameters, never SQL text.

extension SQL {
    // MARK: Case conversion and trimming

    public static func upper<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String { call("UPPER", text) }
    public static func lower<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String { call("LOWER", text) }
    /// Removes spaces from both ends.
    public static func trim<T: SQLArgument>(_ text: T) -> Expr<T.Value> where T.Value.NonNull == String { call("TRIM", text) }

    // MARK: Length and search

    // The two overloads of `startsWith` split on the prefix's nullability, as comparisons do, and require
    // `P.Value.NonNull == String` in both, so that a prefix of another type is reported by its type.

    /// Exact, case-sensitive prefix test. PostgreSQL 11+.
    public static func startsWith<T: SQLArgument, P: SQLArgument>(_ text: T, _ prefix: P) -> Expr<T.Value.AsBool>
    where T.Value.NonNull == String, P.Value.NonNull == String, P.Value.AsBool: SQLValue {
        call("STARTS_WITH", text, prefix)
    }
    public static func startsWith<T: SQLArgument, P: SQLArgument>(_ text: T, _ prefix: P) -> Expr<Bool?>
    where T.Value.NonNull == String, P.Value: ExpressibleByNilLiteral, P.Value.NonNull == String {
        call("STARTS_WITH", text, prefix)
    }

    private static func call<Result>(_ name: String, _ arguments: any SQLArgument...) -> Expr<Result> {
        Expr(.function(name, arguments.map(\.sqlNode)))
    }
}
