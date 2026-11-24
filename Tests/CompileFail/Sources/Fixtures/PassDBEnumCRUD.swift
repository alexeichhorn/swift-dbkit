import DBKit

// An enum column, required and nullable, in filters, inserts, conflict updates, updates and active models, and in the
// rows a query reads.

@DatabaseEnum("publication_state")
enum PublicationState { case draft, inReview, published, archived }

/// Written by hand, as any `String`-backed enum can be.
enum ReviewOutcome: String, DatabaseEnum {
    static let typeName = "review_outcome"
    case pending, approved, rejected
}

/// rust-dbkit's `Article` of this fixture, renamed since `PassOrderedComparisonValueAPI.swift` declares one.
@Model(table: "articles")
class PublishedArticleModel {
    @Key var id: Int64
    var slug: String
    var state: PublicationState
    var review: ReviewOutcome?
}

private func readArticles(on db: Database) async throws -> [PublishedArticleModel] {
    try await PublishedArticleModel.query().all(on: db)
}

private func enumColumnsInQueriesAndMutations() {
    _ = PublishedArticleModel.query()
        .filter(PublishedArticleModel.state == .draft)
        .filter(PublishedArticleModel.state != .archived)
        .filter(PublishedArticleModel.state.in([.draft, .published]))
        .filter(PublishedArticleModel.review == nil)
        .filter(PublishedArticleModel.review.in([.pending, .approved]))

    _ = PublishedArticleModel.insert(PublishedArticleModel.Insert(id: 1, slug: "intro-to-rust", state: .draft, review: .pending))
        .onConflict(PublishedArticleModel.slug, doUpdate: PublishedArticleModel.state, PublishedArticleModel.review)
        .returningAll()

    _ = PublishedArticleModel.update()
        .set(PublishedArticleModel.state, to: .published)
        .set(PublishedArticleModel.review, to: .approved)
        .filter(PublishedArticleModel.slug == "intro-to-rust")
        .returningAll()

    _ = PublishedArticleModel.update()
        .set(PublishedArticleModel.review, to: nil)
        .filter(PublishedArticleModel.id == 1)

    var active = ActiveModel<PublishedArticleModel>()
    active.id = 7
    active.slug = "status-active"
    active.state = .inReview
    active.review = nil
    _ = active
}
