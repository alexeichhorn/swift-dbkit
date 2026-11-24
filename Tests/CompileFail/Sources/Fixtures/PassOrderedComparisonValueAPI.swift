import DBKit
import Foundation

/// rust-dbkit's `Article`, with a column of each other value type PostgreSQL orders.
@Model(table: "articles")
class ArticleModel {
    @Key var id: Int64
    var slug: String
    var attempts: Int64
    var publishedAt: Date
    var priority: Int16
    var rank: Int32
    var position: Int
    var ratio: Float
    var score: Double
    var price: Decimal
    var externalID: UUID
    var archivedAt: Date?
}

// rust-dbkit compares with wrapper types that convert into a bind value. Swift has no such conversion, so the values
// are of the column's type.
private func orderedComparisonsTakeValues() {
    let publishedCutoff = Date(timeIntervalSince1970: 1_700_000_000)

    _ = ArticleModel.query()
        .filter(ArticleModel.attempts >= 3)
        .filter(ArticleModel.publishedAt < publishedCutoff)
}

private func everyOrderedTypeComparesWithValuesAndColumns() {
    let externalID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    _ = ArticleModel.query()
        .filter(ArticleModel.slug < "m")
        .filter(ArticleModel.priority <= 2)
        .filter(ArticleModel.rank > 3)
        .filter(ArticleModel.position >= 4)
        .filter(ArticleModel.ratio < 0.5)
        .filter(ArticleModel.score <= 2.25)
        .filter(ArticleModel.price > Decimal(string: "9.99")!)
        .filter(ArticleModel.externalID >= externalID)
        .filter(ArticleModel.archivedAt < Date(timeIntervalSince1970: 0))

    let _: Expr<Bool> = ArticleModel.slug < ArticleModel.slug
    let _: Expr<Bool> = ArticleModel.attempts <= ArticleModel.attempts
    let _: Expr<Bool> = ArticleModel.priority > ArticleModel.priority
    let _: Expr<Bool> = ArticleModel.rank >= ArticleModel.rank
    let _: Expr<Bool> = ArticleModel.position < ArticleModel.position
    let _: Expr<Bool> = ArticleModel.ratio <= ArticleModel.ratio
    let _: Expr<Bool> = ArticleModel.score > ArticleModel.score
    let _: Expr<Bool> = ArticleModel.price >= ArticleModel.price
    let _: Expr<Bool> = ArticleModel.externalID < ArticleModel.externalID
    let _: Expr<Bool> = ArticleModel.publishedAt <= ArticleModel.publishedAt
    let _: Expr<Bool?> = ArticleModel.archivedAt > ArticleModel.publishedAt
    let _: Expr<Bool?> = ArticleModel.publishedAt >= ArticleModel.archivedAt
}
