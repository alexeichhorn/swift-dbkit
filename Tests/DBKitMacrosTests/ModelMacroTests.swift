import DBKitMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = [
    "Model": MacroSpec(type: ModelMacro.self, conformances: ["Model", "Sendable"]),
    "Key": MacroSpec(type: MarkerMacro.self),
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
}
