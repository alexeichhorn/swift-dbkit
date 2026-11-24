import DBKitMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = [
    "DatabaseEnum": MacroSpec(type: DatabaseEnumMacro.self, conformances: ["DatabaseEnum"])
]

@Suite struct DatabaseEnumMacroTests {
    @Test func labelsAreSnakeCaseCaseNames() {
        assertMacroExpansion(
            """
            @DatabaseEnum("order_state")
            public enum OrderState {
                case pendingReview, running
                case userID
            }
            """,
            expandedSource: """
                public enum OrderState {
                    case pendingReview, running
                    case userID
                }

                extension OrderState: DBKit.DatabaseEnum {
                    public static let typeName = "order_state"

                    public var rawValue: String {
                        switch self {
                        case .pendingReview:
                            "pending_review"
                        case .running:
                            "running"
                        case .userID:
                            "user_id"
                        }
                    }

                    public init?(rawValue: String) {
                        switch rawValue {
                        case "pending_review":
                            self = .pendingReview
                        case "running":
                            self = .running
                        case "user_id":
                            self = .userID
                        default:
                            return nil
                        }
                    }
                }
                """,
            macroSpecs: macros,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test(arguments: [
        (
            """
            struct Status {
            }
            """, "@DatabaseEnum must be applied to an enum"
        ),
        (
            """
            enum Status: String {
                case running
            }
            """, "remove the raw type of 'Status'; @DatabaseEnum generates the labels from the case names"
        ),
        (
            """
            enum Status {
                case failed(reason: String)
            }
            """, "@DatabaseEnum case 'failed' can't have associated values; a PostgreSQL enum value is only a label"
        ),
        (
            """
            enum Status {
                case pendingReview
                case pending_review
            }
            """, "@DatabaseEnum cases 'pendingReview' and 'pending_review' both get the label 'pending_review'; rename one"
        ),
    ])
    func rejects(declaration: String, message: String) {
        assertMacroExpansion(
            """
            @DatabaseEnum("status")
            \(declaration)
            """,
            expandedSource: declaration,
            diagnostics: [DiagnosticSpec(message: message, line: 1, column: 1)],
            macroSpecs: macros,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}
