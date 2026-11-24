import DBKit

// A `@HasMany` takes its foreign key from the target's one `@BelongsTo` back to this model. With two, it must name it.
// The error is reported where `@Model` adds its members: at the closing brace.

@Model(table: "authors")
class AuthorModel {
    @Key @AutoIncrement var id: Int64
    @HasMany var reviews: [ReviewModel]
}  // error: ReviewModel has several @BelongsTo relations to AuthorModel; pass key: to its @HasMany

@Model(table: "reviews")
class ReviewModel {
    @Key @AutoIncrement var id: Int64
    var writerID: Int64
    var editorID: Int64?
    @BelongsTo(key: "writerID") var writer: AuthorModel?
    @BelongsTo(key: "editorID") var editor: AuthorModel?
}
