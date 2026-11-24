/// Typed SQL functions. Results keep the nullability of their inputs where PostgreSQL propagates NULL.
public enum SQL {
    // MARK: Intervals

    public static func interval<E: SQLArgument>(days: E) -> Expr<E.Value.AsInterval> where E.Value.NonNull: SQLNumeric {
        scaledInterval(days, unit: "1 day")
    }

    public static func interval<E: SQLArgument>(hours: E) -> Expr<E.Value.AsInterval> where E.Value.NonNull: SQLNumeric {
        scaledInterval(hours, unit: "1 hour")
    }

    public static func interval<E: SQLArgument>(minutes: E) -> Expr<E.Value.AsInterval> where E.Value.NonNull: SQLNumeric {
        scaledInterval(minutes, unit: "1 minute")
    }

    public static func interval<E: SQLArgument>(seconds: E) -> Expr<E.Value.AsInterval> where E.Value.NonNull: SQLNumeric {
        scaledInterval(seconds, unit: "1 second")
    }

    private static func scaledInterval<E: SQLArgument>(_ amount: E, unit: String) -> Expr<E.Value.AsInterval> {
        Expr(.sequence([.raw("("), amount.sqlNode, .raw(" * INTERVAL '\(unit)')")]))
    }
}
