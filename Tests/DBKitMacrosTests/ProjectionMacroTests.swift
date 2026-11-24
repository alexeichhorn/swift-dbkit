import DBKitMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = ["Projection": MacroSpec(type: ProjectionMacro.self)]

@Suite struct ProjectionMacroTests {
    @Test func columnsTakeOneExpressionPerStoredProperty() {
        assertMacroExpansion(
            """
            @Projection
            public struct RegionTotal {
                public let region: String
                var newest: Date? { didSet {} }
                let version = 1
                static let limit = 10
                var isEmpty: Bool { newest == nil }
            }
            """,
            expandedSource: """
                public struct RegionTotal {
                    public let region: String
                    var newest: Date? { didSet {} }
                    let version = 1
                    static let limit = 10
                    var isEmpty: Bool { newest == nil }

                    /// The select list for this projection: the SQL expression of every property.
                    public static func columns(
                        region: some DBKit.SQLExpression<String>,
                        newest: some DBKit.SQLExpression<Date?>
                    ) -> DBKit.ProjectionColumns<Self> {
                        DBKit.ProjectionColumns([region.sqlNode, newest.sqlNode]) { row in
                            try Self(region: row.next(), newest: row.next())
                        }
                    }
                }
                """,
            macroSpecs: macros,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test func rejectsClasses() {
        assertMacroExpansion(
            """
            @Projection
            class RegionTotal {
                let region: String
            }
            """,
            expandedSource: """
                class RegionTotal {
                    let region: String
                }
                """,
            diagnostics: [DiagnosticSpec(message: "@Projection must be applied to a struct", line: 1, column: 1)],
            macroSpecs: macros,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test func rejectsPropertiesWithoutTypeAnnotation() {
        assertMacroExpansion(
            """
            @Projection
            struct RegionTotal {
                var region = ""
            }
            """,
            expandedSource: """
                struct RegionTotal {
                    var region = ""
                }
                """,
            diagnostics: [DiagnosticSpec(message: "@Projection needs a type annotation on 'region'", line: 1, column: 1)],
            macroSpecs: macros,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test func rejectsStructsWithoutStoredProperties() {
        assertMacroExpansion(
            """
            @Projection
            struct RegionTotal {
                let version = 1
                var isEmpty: Bool { true }
            }
            """,
            expandedSource: """
                struct RegionTotal {
                    let version = 1
                    var isEmpty: Bool { true }
                }
                """,
            diagnostics: [DiagnosticSpec(message: "@Projection needs at least one stored property", line: 1, column: 1)],
            macroSpecs: macros,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}
