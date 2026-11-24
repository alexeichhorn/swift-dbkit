/// The load state of one relation on a loaded row: ``NotLoaded``, `Target?` (loaded to-one) or `[Target]`
/// (loaded to-many). `Target` may itself be a loaded row, e.g. `[TodoModel.Loaded<…>]` after a nested load.
public protocol RelationState: Sendable {}

/// The state of a relation that wasn't loaded.
public struct NotLoaded: RelationState, Hashable {
    public init() {}
}

/// A loaded to-one relation. Generated code uses it to expose the row under the relation's name.
public protocol LoadedToOne: RelationState {
    associatedtype Row: Model
    var row: Row? { get }
}

/// A loaded to-many relation. Generated code uses it to expose the rows under the relation's name.
public protocol LoadedToMany: RelationState {
    associatedtype Row: Model
    var rows: [Row] { get }
}

extension Optional: RelationState, LoadedToOne where Wrapped: Model {
    public var row: Wrapped? { self }
}

extension Array: RelationState, LoadedToMany where Element: Model {
    public var rows: [Element] { self }
}
