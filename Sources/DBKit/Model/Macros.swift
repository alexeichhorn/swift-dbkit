/// Generates the ``Model`` conformance: static typed columns and relations, a memberwise initializer, the `Insert`
/// type, row decoding, and for models with relations the `Loaded` subclass plus one `With…` type per relation.
///
/// Models are classes, so a row with loaded relations (a `Loaded` subclass instance) can be passed wherever the plain
/// model is expected. Columns are `var`s that `@Model` makes read-only; a Swift default (`var isComplete = false`)
/// becomes the default in `Insert`. Relation properties are declared with their loaded type and are unavailable on the
/// plain model; reading one compiles only after `.with(\.relation)`. Property names starting with `__dbkit_` are
/// reserved for the generated code.
///
/// Column names default to the snake_case property name (`userID` → `user_id`); override with ``ColumnName(_:)``.
/// The table name defaults to the snake_case type name.
///
/// ```swift
/// @Model(table: "todos")
/// class TodoModel {
///     @Key @AutoIncrement var id: Int64
///     var userID: Int64
///     var title: String
///     var isComplete: Bool = false
///     @BelongsTo(key: "userID") var user: UserModel?
/// }
///
/// func notify(_ todo: TodoModel) { … }                  // any todo row
/// func notifyOwner(of todo: TodoModel.WithUser) { … }   // only rows loaded with .with(\.user)
/// ```
@attached(member, names: arbitrary)
@attached(memberAttribute)
@attached(
    extension, conformances: Model, Sendable, names: named(Base), named(schema), named(decodeBase), named(columnName), named(base),
    named(columnValues))
public macro Model(table: String? = nil) = #externalMacro(module: "DBKitMacros", type: "ModelMacro")

/// Makes a column read-only. `@Model` adds it to every column; not meant to be written by hand.
@attached(accessor, names: named(init), named(get))
public macro _Column() = #externalMacro(module: "DBKitMacros", type: "ColumnMacro")

/// Adds the generated `extension <attached type><code>`. Used by `@Model` for the accessors of its relation
/// protocols; not meant to be written by hand.
@attached(extension, names: arbitrary)
public macro _Extension(_ code: String) = #externalMacro(module: "DBKitMacros", type: "ExtensionCodeMacro")

/// Marks a primary-key column. Several `@Key` properties form a composite key.
@attached(peer)
public macro Key() = #externalMacro(module: "DBKitMacros", type: "MarkerMacro")

/// Marks a column whose value the database generates on insert; it's left out of the `Insert` type.
@attached(peer)
public macro AutoIncrement() = #externalMacro(module: "DBKitMacros", type: "MarkerMacro")

/// Documents a unique constraint. Metadata only: DBKit doesn't manage the schema.
@attached(peer)
public macro Unique() = #externalMacro(module: "DBKitMacros", type: "MarkerMacro")

/// Documents an index. Metadata only: DBKit doesn't manage the schema.
@attached(peer)
public macro Index() = #externalMacro(module: "DBKitMacros", type: "MarkerMacro")

/// Overrides the column name, e.g. `@ColumnName("type") var kind: String`.
@attached(peer)
public macro ColumnName(_ name: String) = #externalMacro(module: "DBKitMacros", type: "MarkerMacro")

/// A to-one relation through a foreign key on this model, declared with its loaded type: `var user: UserModel?`.
///
/// - Parameters:
///   - key: The foreign-key property on this model.
///   - references: The referenced property on the target; must be unique.
@attached(accessor)
public macro BelongsTo(key: String, references: String = "id") = #externalMacro(module: "DBKitMacros", type: "RelationMacro")

/// A to-many relation through a foreign key on the target model, declared with its loaded type:
/// `var todos: [TodoModel]`.
///
/// Without `key:`, the foreign key and referenced property come from the target's one `@BelongsTo` back to this model.
///
/// - Parameters:
///   - key: The foreign-key property on the target. Required when the target has several `@BelongsTo` to this model.
///   - references: The property on this model the foreign key references.
@attached(accessor)
public macro HasMany(key: String? = nil, references: String = "id") = #externalMacro(module: "DBKitMacros", type: "RelationMacro")

/// A to-many relation through a join model, declared with its loaded type: `var tags: [TagModel]`.
///
/// - Parameters:
///   - through: The join model.
///   - from: The join model's property referencing this model's `id`.
///   - to: The join model's property referencing the target's `id`.
@attached(accessor)
public macro ManyToMany<Through: Model>(through: Through.Type, from: String, to: String) =
    #externalMacro(module: "DBKitMacros", type: "RelationMacro")

/// Makes a struct the typed result of a `SELECT`. Generates `columns(…)` with one labelled parameter per stored
/// property, each taking the SQL expression for it, so a missing column, a misspelled name and a wrong type are
/// compile errors:
/// `.select(Contact.columns(name: UserModel.name, isUS: UserModel.region == "us"))`.
///
/// The struct must be `Sendable` and keep its memberwise initializer, and every stored property needs a type
/// annotation. A public struct has to declare `Sendable` itself.
@attached(member, names: named(columns))
public macro Projection() = #externalMacro(module: "DBKitMacros", type: "ProjectionMacro")
