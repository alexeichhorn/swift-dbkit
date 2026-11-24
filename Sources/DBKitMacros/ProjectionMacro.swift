import SwiftSyntax
import SwiftSyntaxMacros

/// Expands `@Projection` on a struct to `columns(…)`, which takes one SQL expression per stored property and returns
/// the select list that decodes into the struct.
public struct ProjectionMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@Projection must be applied to a struct")
        }
        var properties: [(name: String, type: String)] = []
        for member in structDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) })
            else { continue }
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text, binding.isStored else { continue }
                // A `let` with a value isn't part of the memberwise initializer.
                if variable.bindingSpecifier.tokenKind == .keyword(.let), binding.initializer != nil { continue }
                guard let type = binding.typeAnnotation?.type.trimmedDescription else {
                    throw MacroExpansionErrorMessage("@Projection needs a type annotation on '\(name)'")
                }
                properties.append((name, type))
            }
        }
        guard !properties.isEmpty else {
            throw MacroExpansionErrorMessage("@Projection needs at least one stored property")
        }

        let access = structDecl.modifiers.first { ["public", "package"].contains($0.name.text) }.map { $0.name.text + " " } ?? ""
        let parameters = properties.map { "\($0.name): some DBKit.SQLExpression<\($0.type)>" }
        let nodes = properties.map { "\($0.name).sqlNode" }
        let arguments = properties.map { "\($0.name): row.next()" }
        return [
            """
            /// The select list for this projection: the SQL expression of every property.
            \(raw: access)static func columns(
                \(raw: parameters.joined(separator: ",\n    "))
            ) -> DBKit.ProjectionColumns<Self> {
                DBKit.ProjectionColumns([\(raw: nodes.joined(separator: ", "))]) { row in
                    try Self(\(raw: arguments.joined(separator: ", ")))
                }
            }
            """
        ]
    }
}

extension PatternBindingSyntax {
    /// False for computed properties; observed properties (`willSet`/`didSet`) are stored.
    fileprivate var isStored: Bool {
        switch accessorBlock?.accessors {
        case nil: true
        case .getter?: false
        case .accessors(let accessors)?: accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
        }
    }
}
