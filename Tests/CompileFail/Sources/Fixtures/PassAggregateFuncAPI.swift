import DBKit
import Foundation

/// rust-dbkit's `Sale` of `pass_aggregate_func_api.rs`, with `Decimal` columns besides. `Date` stands in for its
/// `timestamp` column.
@Model(table: "sales")
class AggregateSaleModel {
    @Key var id: Int64
    var region: String
    var note: String?
    var smallAmount: Int16
    var nullableSmallAmount: Int16?
    var integerAmount: Int32
    var nullableIntegerAmount: Int32?
    var amount: Int64
    var nullableAmount: Int64?
    var realAmount: Float
    var nullableRealAmount: Float?
    var doubleAmount: Double
    var nullableDoubleAmount: Double?
    var decimalAmount: Decimal
    var nullableDecimalAmount: Decimal?
    var createdAt: Date
}

private typealias S = AggregateSaleModel

// `SUM`, `MIN` and `MAX` return NULL without input rows, so they are optional; a nullable input doesn't nest the
// optional. `SUM` takes PostgreSQL's result type: `smallint` and `integer` sum to `bigint`, `bigint` and `numeric` to
// `numeric`, and `real` and `double precision` keep their type. rust-dbkit keeps the input type. `COUNT` is never NULL.
private func aggregatesTakePostgreSQLResultTypes() {
    let _: AggregateExpr<Date?> = SQL.min(S.createdAt)
    let _: AggregateExpr<Date?> = SQL.max(S.createdAt)
    let _: AggregateExpr<Int64?> = SQL.min(S.amount)
    let _: AggregateExpr<Int64?> = SQL.max(S.amount)
    let _: AggregateExpr<String?> = SQL.min(S.note)
    let _: AggregateExpr<String?> = SQL.max(S.note)

    let _: AggregateExpr<Int64?> = SQL.sum(S.smallAmount)
    let _: AggregateExpr<Int64?> = SQL.sum(S.nullableSmallAmount)
    let _: AggregateExpr<Int64?> = SQL.sum(S.integerAmount)
    let _: AggregateExpr<Int64?> = SQL.sum(S.nullableIntegerAmount)
    let _: AggregateExpr<Decimal?> = SQL.sum(S.amount)
    let _: AggregateExpr<Decimal?> = SQL.sum(S.nullableAmount)
    let _: AggregateExpr<Float?> = SQL.sum(S.realAmount)
    let _: AggregateExpr<Float?> = SQL.sum(S.nullableRealAmount)
    let _: AggregateExpr<Double?> = SQL.sum(S.doubleAmount)
    let _: AggregateExpr<Double?> = SQL.sum(S.nullableDoubleAmount)
    let _: AggregateExpr<Decimal?> = SQL.sum(S.decimalAmount)
    let _: AggregateExpr<Decimal?> = SQL.sum(S.nullableDecimalAmount)

    let _: AggregateExpr<Int64> = SQL.count(S.id)
    let _: AggregateExpr<Int64> = SQL.count(S.note)
    let _: AggregateExpr<Int64> = SQL.countAll()
}

// A filtered aggregate keeps its type. `??` is rust-dbkit's `func::coalesce` here.
private func aggregatesProjectFilterGroupAndOrder() {
    let firstSaleAt = SQL.min(S.createdAt)
    let lastSaleAt = SQL.max(S.createdAt)
    let minAmount = SQL.min(S.amount)
    let maxAmount = SQL.max(S.amount)
    let minNote = SQL.min(S.note)
    let maxNote = SQL.max(S.note)
    let usSale = S.region == "us"
    let usSaleCount: Expr<Int64> = SQL.count(S.id).filter(usSale)
    let firstUSSaleAt: Expr<Date?> = SQL.min(S.createdAt).filter(usSale)
    let filteredUSTotal: Expr<Decimal?> = SQL.sum(S.amount).filter(S.region == "us")
    let guaranteedTotal: Expr<Decimal> = SQL.sum(S.amount) ?? 0

    let query: Projection<String, Date?, Date?, Int64?, Int64?, String?, String?, Int64, Date?, Decimal?, Decimal> = S.query()
        .select(
            S.region.as("region"),
            firstSaleAt.as("first_sale_at"),
            lastSaleAt.as("last_sale_at"),
            minAmount.as("min_amount"),
            maxAmount.as("max_amount"),
            minNote.as("min_note"),
            maxNote.as("max_note"),
            usSaleCount.as("us_sale_count"),
            firstUSSaleAt.as("first_us_sale_at"),
            filteredUSTotal.as("filtered_us_total"),
            guaranteedTotal.as("guaranteed_total")
        )
        .groupBy(S.region)
        .having(maxAmount > 100)
        .orderBy(firstSaleAt.asc)
    _ = query.render()
}

// Comparing an aggregate follows the nullability rule, and `having` and an aggregate's `filter` take both results.
private func aggregateComparisonsFollowTheNullabilityRule() {
    let _: Expr<Bool> = SQL.count(S.id) > 1
    let _: Expr<Bool> = SQL.countAll() > 1
    let _: Expr<Bool?> = SQL.sum(S.amount) > 100
    let _: Expr<Bool?> = SQL.max(S.amount) > 100
    let _: Expr<Bool?> = SQL.min(S.note) == "alpha"

    let nullable: Expr<Bool?> = S.note == "promo"
    _ = S.query().groupBy(S.region).having(SQL.count(S.id) > 1).having(SQL.sum(S.amount) > 100).render()
    let _: Expr<Int64> = SQL.count(S.id).filter(nullable)
    let _: Expr<Decimal?> = SQL.sum(S.amount).filter(nullable)
}

// Aggregates take computed values, and their results compute further: casts, `??` and arithmetic.
private func aggregatesComposeWithArithmeticAndCasts() {
    let _: AggregateExpr<Int64?> = SQL.sum(S.integerAmount * 2)
    let _: AggregateExpr<Int64?> = SQL.sum(S.smallAmount + S.smallAmount)
    let _: AggregateExpr<Decimal?> = SQL.sum(S.amount - S.nullableAmount)
    let _: AggregateExpr<Decimal?> = SQL.sum(S.nullableAmount ?? 0)
    let _: AggregateExpr<Double?> = SQL.sum(S.integerAmount.cast(to: Double.self))
    let _: AggregateExpr<Int64?> = SQL.max(S.amount + S.nullableAmount)

    let _: Expr<Double?> = SQL.sum(S.amount).cast(to: Double.self)
    let _: Expr<Double?> = SQL.sum(S.amount).filter(S.region == "us").cast(to: Double.self)
    let _: Expr<Int64> = SQL.sum(S.integerAmount) ?? 0
    let _: Expr<Decimal> = SQL.sum(S.amount).filter(S.region == "us") ?? 0
    let _: Expr<Int64?> = SQL.max(S.amount) - SQL.min(S.amount)
    let _: Expr<Double?> = SQL.sum(S.doubleAmount) / SQL.count(S.id).cast(to: Double.self)
}
