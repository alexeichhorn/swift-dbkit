/// Generates the ``Model`` conformance: static typed columns, a memberwise initializer, the `Insert` type, row decoding
/// and, for a single primary key, `find(_:on:)`.
///
/// Models are classes, so a row with loaded relations can be passed wherever the plain model is expected. Columns are
/// `var`s that `@Model` makes read-only; a Swift default (`var isComplete = false`) becomes the default in `Insert`.
/// Property names starting with `__dbkit_` are reserved for the generated code.
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
/// }
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

/// Makes a struct the typed result of a `SELECT`. Generates `columns(…)` with one labelled parameter per stored
/// property, each taking the SQL expression for it, so a missing column, a misspelled name and a wrong type are
/// compile errors:
/// `.select(Contact.columns(name: UserModel.name, isUS: UserModel.region == "us"))`.
///
/// The struct must be `Sendable` and keep its memberwise initializer, and every stored property needs a type
/// annotation. A public struct has to declare `Sendable` itself.
@attached(member, names: named(columns))
public macro Projection() = #externalMacro(module: "DBKitMacros", type: "ProjectionMacro")
