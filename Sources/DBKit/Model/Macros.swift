/// Generates the ``Model`` conformance: static typed columns, a memberwise initializer, row decoding and, for a single
/// primary key, `find(_:on:)`.
///
/// Models are classes, so a row with loaded relations can be passed wherever the plain model is expected. Columns are
/// `var`s that `@Model` makes read-only; a Swift default (`var isComplete = false`) becomes the initializer's default.
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
@attached(extension, conformances: Model, Sendable, names: named(Base), named(schema), named(decodeBase))
public macro Model(table: String? = nil) = #externalMacro(module: "DBKitMacros", type: "ModelMacro")

/// Makes a column read-only. `@Model` adds it to every column; not meant to be written by hand.
@attached(accessor, names: named(init), named(get))
public macro _Column() = #externalMacro(module: "DBKitMacros", type: "ColumnMacro")

/// Marks a primary-key column. Several `@Key` properties form a composite key.
@attached(peer)
public macro Key() = #externalMacro(module: "DBKitMacros", type: "MarkerMacro")

/// Marks a column whose value the database generates on insert.
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
