import DBKitMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = [
    "Model": MacroSpec(type: ModelMacro.self, conformances: ["Model", "Sendable"]),
    "Key": MacroSpec(type: MarkerMacro.self),
    "AutoIncrement": MacroSpec(type: MarkerMacro.self),
]

/// The generated code itself is covered by compiling the test models; these check the mistakes `@Model` explains.
@Suite struct ModelMacroTests {
    @Test func rejectsLetColumns() {
        assertMacroExpansion(
            """
            @Model(table: "notes")
            class NoteModel {
                @Key let id: Int64
            }
            """,
            expandedSource: """
                class NoteModel {
                    let id: Int64
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "column 'id' must be a `var`; @Model makes it read-only, change rows with update() or active()",
                    line: 1,
                    column: 1
                )
            ],
            macroSpecs: macros,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test func rejectsStructs() {
        assertMacroExpansion(
            """
            @Model(table: "notes")
            struct NoteModel {
                @Key let id: Int64
            }
            """,
            expandedSource: """
                struct NoteModel {
                    let id: Int64
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "@Model must be applied to a class, so rows with loaded relations can be passed where the plain model is expected",
                    line: 1,
                    column: 1
                )
            ],
            macroSpecs: macros,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test func rejectsAutoIncrementDefaults() {
        assertMacroExpansion(
            """
            @Model(table: "notes")
            class NoteModel {
                @Key @AutoIncrement var id: Int64 = 0
            }
            """,
            // Removing the marker attributes leaves a line of indentation behind.
            expandedSource: """
                class NoteModel {
                \("    ")
                    @DBKit._Column var id: Int64 = 0
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@AutoIncrement column 'id' can't have a Swift default; the database assigns the value",
                    line: 1,
                    column: 1
                )
            ],
            macroSpecs: macros,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    /// Mistakes in the class and its relations, each with the message `@Model` reports on its attribute.
    @Test(arguments: [
        Mistake(
            source: """
                @Model(table: "notes")
                final class NoteModel {
                    var id: Int64
                }
                """,
            expanded: """
                final class NoteModel {
                    @DBKit._Column
                    var id: Int64
                }
                """,
            message: "@Model classes can't be final: rows with loaded relations are a generated subclass"
        ),
        Mistake(
            source: """
                @Model(table: "notes")
                class NoteModel<State> {
                    var id: Int64
                }
                """,
            expanded: """
                class NoteModel<State> {
                    @DBKit._Column
                    var id: Int64
                }
                """,
            message: "@Model classes can't be generic; declare relations as properties of their loaded type"
        ),
        Mistake(
            source: """
                @Model(table: "todos")
                class TodoModel {
                    @BelongsTo(key: "userID") let user: UserModel?
                }
                """,
            expanded: """
                class TodoModel {
                    @BelongsTo(key: "userID") let user: UserModel?
                }
                """,
            message: "relation 'user' must be a `var`; it's generated as an accessor"
        ),
        Mistake(
            source: """
                @Model(table: "todos")
                class TodoModel {
                    @BelongsTo(key: "userID") var user: UserModel
                }
                """,
            expanded: #"""
                class TodoModel {
                    @BelongsTo(key: "userID")
                    @available(*, unavailable, message: "relation 'user' is not loaded; add .with(\\.user) to the query") var user: UserModel
                }
                """#,
            message: "@BelongsTo relation 'user' must have an optional model type, e.g. `UserModel?`"
        ),
        Mistake(
            source: """
                @Model(table: "users")
                class UserModel {
                    @HasMany var todos: TodoModel?
                }
                """,
            expanded: #"""
                class UserModel {
                    @HasMany
                    @available(*, unavailable, message: "relation 'todos' is not loaded; add .with(\\.todos) to the query") var todos: TodoModel?
                }
                """#,
            message: "@HasMany relation 'todos' must have an array type, e.g. `[TodoModel]`"
        ),
        Mistake(
            source: """
                @Model(table: "todos")
                class TodoModel {
                    @BelongsTo(key: userKey) var user: UserModel?
                }
                """,
            expanded: #"""
                class TodoModel {
                    @BelongsTo(key: userKey)
                    @available(*, unavailable, message: "relation 'user' is not loaded; add .with(\\.user) to the query") var user: UserModel?
                }
                """#,
            message: "@BelongsTo on 'user' needs a string literal `key:` argument"
        ),
        Mistake(
            source: """
                @Model(table: "users")
                class UserModel {
                    @HasMany(references: "email") var todos: [TodoModel]
                }
                """,
            expanded: #"""
                class UserModel {
                    @HasMany(references: "email")
                    @available(*, unavailable, message: "relation 'todos' is not loaded; add .with(\\.todos) to the query") var todos: [TodoModel]
                }
                """#,
            message: "@HasMany on 'todos' needs `key:` when it sets `references:`"
        ),
        Mistake(
            source: """
                @Model(table: "todos")
                class TodoModel {
                    @ManyToMany(through: joinModel, from: "todoID", to: "tagID") var tags: [TagModel]
                }
                """,
            expanded: #"""
                class TodoModel {
                    @ManyToMany(through: joinModel, from: "todoID", to: "tagID")
                    @available(*, unavailable, message: "relation 'tags' is not loaded; add .with(\\.tags) to the query") var tags: [TagModel]
                }
                """#,
            message: "@ManyToMany on 'tags' needs a join model like `through: TodoTagModel.self`"
        ),
    ])
    func rejectsMisdeclaredModelsAndRelations(_ mistake: Mistake) {
        assertMacroExpansion(
            mistake.source,
            expandedSource: mistake.expanded,
            diagnostics: [DiagnosticSpec(message: mistake.message, line: 1, column: 1)],
            macroSpecs: macros,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    struct Mistake: Sendable, CustomTestStringConvertible {
        let source: String
        let expanded: String
        let message: String

        var testDescription: String { message }
    }
}
