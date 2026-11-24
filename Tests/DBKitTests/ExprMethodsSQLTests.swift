import DBKit
import Foundation
import Testing

/// rust-dbkit's `samples` of `expr_methods_sql.rs`, which types its columns per test. `label` is nullable as in most of
/// them, and `requiredLabel` stands in where a test reads `label` as required text.
@Model(table: "samples")
class ExprMethodSampleModel {
    @Key var id: Int64
    var label: String?
    var requiredLabel: String
    var prefix: String
    var optionalPrefix: String?
    var count: Int32?
    var fallback: Int32
    var amount: Int64
}

private typealias S = ExprMethodSampleModel

/// `??` is rust-dbkit's `unwrap_or`.
@Suite struct ExprMethodsSQLTests {
    @Test func unwrapOrAcceptsLiteralsColumnsAndExpressions() {
        let label: Expr<String> = S.label ?? "unknown"
        let count: Expr<Int32> = S.count ?? S.fallback
        let computed: Expr<Int32> = (S.count + 1) ?? (S.fallback + 2)
        let ready: Expr<Bool> = (S.label == "ready") ?? false
        let rendered = S.query()
            .select(label.as("label"), count.as("count"), computed.as("computed"), ready.as("ready"))
            .render()
        #expect(
            rendered.sql
                == #"SELECT COALESCE("samples"."label", $1) AS "label", COALESCE("samples"."count", "samples"."fallback") AS "count", COALESCE(("samples"."count" + $2), ("samples"."fallback" + $3)) AS "computed", COALESCE("samples"."label" = $4, $5) AS "ready" FROM "samples""#
        )
        #expect(rendered.binds.map(\.description) == ["unknown", "1", "2", "ready", "false"])
    }

    @Test func stringMethodsChainInProjectionsFiltersAndOrdering() {
        let normalized: Expr<String> = S.label.trimmed().lowercased() ?? "missing"
        let rendered = S.query()
            .select(normalized.as("normalized"))
            .filter(normalized.hasPrefix("a"))
            .orderBy(normalized.asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT COALESCE(LOWER(TRIM("samples"."label")), $1) AS "normalized" FROM "samples" WHERE STARTS_WITH(COALESCE(LOWER(TRIM("samples"."label")), $2), $3) ORDER BY COALESCE(LOWER(TRIM("samples"."label")), $4) ASC"#
        )
        #expect(rendered.binds.map(\.description) == ["missing", "missing", "a", "missing"])
    }

    @Test func stringMethodsMatchExistingFunctionsForRequiredAndNullableInputs() {
        expectSameSQL(S.requiredLabel.trimmed(), SQL.trim(S.requiredLabel))
        expectSameSQL(S.label.trimmed(), SQL.trim(S.label))
        expectSameSQL(S.requiredLabel.lowercased(), SQL.lower(S.requiredLabel))
        expectSameSQL(S.label.lowercased(), SQL.lower(S.label))
        expectSameSQL(SQL.upper(S.requiredLabel).trimmed(), SQL.trim(SQL.upper(S.requiredLabel)))
        expectSameSQL(SQL.upper(S.label).lowercased(), SQL.lower(SQL.upper(S.label)))
        expectSameSQL(S.requiredLabel.hasPrefix(S.prefix), SQL.startsWith(S.requiredLabel, S.prefix))
        expectSameSQL(S.label.hasPrefix(S.optionalPrefix), SQL.startsWith(S.label, S.optionalPrefix))
        expectSameSQL(
            S.requiredLabel.lowercased().hasPrefix(S.prefix.lowercased()),
            SQL.startsWith(SQL.lower(S.requiredLabel), SQL.lower(S.prefix))
        )
    }

    @Test func startsWithBindsLiteralPrefixesWithoutLikeEscaping() {
        let prefix = "'%_\\🦀"
        let rendered = S.query()
            .select(S.requiredLabel.hasPrefix(prefix).as("literal"), S.label.hasPrefix("").as("empty"))
            .render()
        #expect(
            rendered.sql
                == #"SELECT STARTS_WITH("samples"."required_label", $1) AS "literal", STARTS_WITH("samples"."label", $2) AS "empty" FROM "samples""#
        )
        #expect(rendered.binds.map(\.description) == [prefix, ""])
    }

    /// PostgreSQL sums `bigint` as `numeric`, so the sums are `Decimal`.
    @Test func methodsWrapAggregatesAfterTheirFilterClause() {
        let total: Expr<Decimal> = SQL.sum(S.amount) ?? 0
        let positiveTotal: Expr<Decimal> = SQL.sum(S.amount).filter(S.amount > 0) ?? 0
        let firstLabel: Expr<String> = SQL.min(S.label).trimmed().lowercased() ?? "empty"
        let rendered = S.query()
            .select(total.as("total"), positiveTotal.as("positive_total"), firstLabel.as("first_label"))
            .render()
        #expect(
            rendered.sql
                == #"SELECT COALESCE(SUM("samples"."amount"), $1) AS "total", COALESCE(SUM("samples"."amount") FILTER (WHERE "samples"."amount" > $2), $3) AS "positive_total", COALESCE(LOWER(TRIM(MIN("samples"."label"))), $4) AS "first_label" FROM "samples""#
        )
        #expect(rendered.binds.map(\.description) == ["0", "0", "0", "empty"])
    }

    /// A method and the function it stands for render the same SQL and have the same type.
    private func expectSameSQL<Method: SQLExpression, Function: SQLExpression>(
        _ method: Method, _ function: Function, sourceLocation: SourceLocation = #_sourceLocation
    ) where Method.Value == Function.Value {
        let methodSQL = S.query().select(method.as("value")).render()
        let functionSQL = S.query().select(function.as("value")).render()
        #expect(methodSQL.sql == functionSQL.sql, sourceLocation: sourceLocation)
        #expect(methodSQL.binds.map(\.description) == functionSQL.binds.map(\.description), sourceLocation: sourceLocation)
    }
}
