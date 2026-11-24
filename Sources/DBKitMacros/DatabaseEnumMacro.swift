import SwiftSyntax
import SwiftSyntaxMacros

/// Expands `@DatabaseEnum("type_name")` on a plain enum to its `DatabaseEnum` conformance. The label of a case is its
/// snake_case name, the rule `@Model` uses for column names.
public struct DatabaseEnumMacro: ExtensionMacro {
    /// The standard-library types an enum can declare as its raw type.
    private static let rawTypes: Set = [
        "String", "Character", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Float", "Double",
    ]

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@DatabaseEnum must be applied to an enum")
        }
        guard let typeName = node.arguments?.as(LabeledExprListSyntax.self)?.first.flatMap({ stringLiteral($0.expression) }) else {
            throw MacroExpansionErrorMessage("@DatabaseEnum needs the PostgreSQL type name as a string literal")
        }
        let hasRawType = enumDecl.inheritanceClause?.inheritedTypes.contains { rawTypes.contains($0.type.trimmedDescription) } ?? false
        guard !hasRawType else {
            throw MacroExpansionErrorMessage(
                "remove the raw type of '\(enumDecl.name.text)'; @DatabaseEnum generates the labels from the case names")
        }
        let elements = enumDecl.memberBlock.members.flatMap { $0.decl.as(EnumCaseDeclSyntax.self).map { Array($0.elements) } ?? [] }
        if let element = elements.first(where: { $0.parameterClause != nil }) {
            throw MacroExpansionErrorMessage(
                "@DatabaseEnum case '\(element.name.text)' can't have associated values; a PostgreSQL enum value is only a label")
        }

        let access = enumDecl.modifiers.first { ["public", "package"].contains($0.name.text) }.map { $0.name.text + " " } ?? ""
        // Backticks escape a keyword used as a case name; they aren't part of the name.
        let cases = elements.map { (name: $0.name.text, label: snakeCased($0.name.text.filter { $0 != "`" })) }
        // Two cases with one label would save alike, and reading would always give back the first.
        var caseOfLabel: [String: String] = [:]
        for item in cases {
            if let first = caseOfLabel.updateValue(item.name, forKey: item.label) {
                throw MacroExpansionErrorMessage(
                    "@DatabaseEnum cases '\(first)' and '\(item.name)' both get the label '\(item.label)'; rename one")
            }
        }
        let code = """
            extension \(type.trimmedDescription): DBKit.DatabaseEnum {
                \(access)static let typeName = "\(typeName)"

                \(access)var rawValue: String {
                    switch self {
                    \(cases.map { "case .\($0.name): \"\($0.label)\"" }.joined(separator: "\n"))
                    }
                }

                \(access)init?(rawValue: String) {
                    switch rawValue {
                    \(cases.map { "case \"\($0.label)\": self = .\($0.name)" }.joined(separator: "\n"))
                    default: return nil
                    }
                }
            }
            """
        return [DeclSyntax(stringLiteral: code).cast(ExtensionDeclSyntax.self)]
    }
}
