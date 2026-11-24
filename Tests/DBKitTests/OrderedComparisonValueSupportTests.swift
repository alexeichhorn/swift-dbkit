import DBKit
import Foundation
import Testing

@Model(table: "articles")
class ArticleModel {
    @Key var id: Int64
    var slug: String
    var attempts: Int64
    var publishedAt: Date
}

@Suite struct OrderedComparisonValueSupportTests {
    /// rust-dbkit compares with wrapper types that convert into a bind value. Swift has no such conversion, so the
    /// values are of the column's type.
    @Test func orderedComparisonPreservesValueConvertibleRHSSupport() throws {
        let publishedCutoff = Date(timeIntervalSince1970: 1_700_000_000)

        let rendered = ArticleModel.query()
            .filter(ArticleModel.attempts >= 3)
            .filter(ArticleModel.publishedAt < publishedCutoff)
            .render()

        #expect(
            rendered.sql == #"SELECT "articles".* FROM "articles" WHERE "articles"."attempts" >= $1 AND "articles"."published_at" < $2"#)
        try #require(rendered.binds.count == 2)
        #expect(rendered.binds[0].value as? Int64 == 3)
        #expect(rendered.binds[1].value as? Date == publishedCutoff)
    }
}
