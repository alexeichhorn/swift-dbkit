/// A relation of `Source` that can be eager-loaded, joined, or used in a relation path.
///
/// `@Model` generates one conforming type per relation, generic over the source row and the loaded child type
/// `Child`. The model's `Relations.user` loads onto a plain row; on an already loaded row,
/// `.with(\.user)` uses the copy in `Loaded.LoadedRelations`, which keeps the relations loaded so far. `Output` is
/// the model's `Loaded` subclass with this relation loaded as `Child?` or `[Child]`; nested loads
/// (`.with(\.todos) { $0.with(\.tags) }`) change `Child` and therefore `Output`.
public protocol RelationLoad: Sendable {
    associatedtype Source: Model
    associatedtype Target: Model where Target.Base == Target
    associatedtype Child: Model where Child.Base == Target
    associatedtype Output: Model where Output.Base == Source.Base

    var relation: Relation { get set }
    /// How loaded children get their own nested relations.
    var plan: LoadPlan<Child> { get }

    /// Creates the loaded row from a source row and its children. Belongs-to relations keep the first child.
    func attach(_ children: [Child], to source: Source) -> Output
}

/// The `Loaded` subclass `@Model` generates for models with relations. `LoadedRelations` holds the relations
/// `.with(_:)` can add to such a row while keeping the ones already loaded.
public protocol LoadedModel: Model {
    associatedtype LoadedRelations
}

/// A to-one relation. Its target's columns and further to-one relations are reachable as a relation path:
/// `TodoModel.Relations.user.name`, `RecordModel.Relations.owner.organization.name`. Path columns are nullable because the
/// `LEFT JOIN` can find no row.
@dynamicMemberLookup
public protocol BelongsToRelation: RelationLoad {}

public protocol HasManyRelation: RelationLoad {}

public protocol ManyToManyRelation: RelationLoad {}

extension BelongsToRelation {
    public subscript<V: SQLType>(dynamicMember column: KeyPath<Target.Type, Column<Target, V>>) -> Expr<V.NonNull?> {
        let name = Target.self[keyPath: column].name
        return Expr(.column(ColumnReference(table: Target.schema.table, name: name, path: relation.path)))
    }

    public subscript<Next: BelongsToRelation>(dynamicMember next: KeyPath<Target.Relations.Type, Next>) -> Next
    where Next.Source == Target {
        var nextRelation = Target.Relations.self[keyPath: next]
        nextRelation.relation.parents = relation.path
        return nextRelation
    }
}

/// How an eager load fetches its rows.
public enum LoadStrategy: Sendable {
    /// One extra query per relation level: `WHERE key = ANY($1)`. Best with `LIMIT`/`OFFSET` and large fan-out.
    case selectIn
    /// A `LEFT JOIN` in the main query, decoded into the tree. One query, but rows multiply per to-many child.
    case joined
}
