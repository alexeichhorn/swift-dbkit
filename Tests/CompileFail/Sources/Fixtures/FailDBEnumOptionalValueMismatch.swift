import DBKit

// A nullable enum column takes optionals of its own enum only, in filters and in updates.

@DatabaseEnum("moderation_state")
enum ModerationState { case pending, approved, rejected }

@DatabaseEnum("visibility_state")
enum VisibilityState { case `public`, `private` }

@Model(table: "posts")
class PostModel {
    @Key var id: Int64
    var moderation: ModerationState?
}

private func optionalsOfAnotherEnum() {
    let hidden: VisibilityState? = .private
    let shown: VisibilityState? = .public
    _ = PostModel.query().filter(PostModel.moderation == hidden)  // error: cannot convert
    _ = PostModel.update().set(PostModel.moderation, to: shown)  // error: cannot convert
}
