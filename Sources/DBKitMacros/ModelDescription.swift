import SwiftSyntax
import SwiftSyntaxMacros

/// The parts of a `@Model` class that code generation needs.
struct ModelDescription {
    struct Field {
        /// The property name as written, with the backticks of a raw identifier.
        let name: String
        let type: String
        let column: String
        /// The private storage behind the read-only property, see ``storageName(of:)``.
        let storage: String
        let isOptional: Bool
        let isKey: Bool
        /// The Swift default from `var x: T = value`, used by the initializer.
        let defaultValue: String?

        /// The default parameter value in the initializer.
        var parameterDefault: String? { defaultValue ?? (isOptional ? "nil" : nil) }
    }

    let name: String
    let access: String
    let table: String
    let fields: [Field]
    /// Property names that use ``reservedPrefix``. The member expansion reports them but still generates the model, so
    /// the compiler adds no follow-up errors.
    let reservedNames: [TokenSyntax]

    var keys: [Field] { fields.filter(\.isKey) }

    init(declaration: some DeclGroupSyntax, attribute: AttributeSyntax) throws {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw MacroExpansionErrorMessage(
                "@Model must be applied to a class, so rows with loaded relations can be passed where the plain model is expected")
        }
        name = classDecl.name.text
        access =
            classDecl.modifiers.first { ["public", "package"].contains($0.name.text) }.map { $0.name.text + " " } ?? ""

        let tableArgument = attribute.arguments?.as(LabeledExprListSyntax.self)?.first { $0.label?.text == "table" }
        table = tableArgument.flatMap { stringLiteral($0.expression) } ?? snakeCased(name)

        var fields: [Field] = []
        var reservedNames: [TokenSyntax] = []
        for member in classDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }),
                let binding = variable.bindings.first
            else { continue }
            // Computed properties are the model's own helpers.
            if binding.accessorBlock != nil { continue }
            if variable.modifiers.contains(where: { $0.name.text == "private" }) { continue }
            guard variable.bindings.count == 1, let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                let typeAnnotation = binding.typeAnnotation
            else {
                throw MacroExpansionErrorMessage("@Model properties need one name and an explicit type")
            }
            let name = identifier.identifier.text
            let plainName = unescapedName(of: identifier.identifier)
            if plainName.hasPrefix(reservedPrefix) { reservedNames.append(identifier.identifier) }

            guard variable.bindingSpecifier.text == "var" else {
                throw MacroExpansionErrorMessage(
                    "column '\(name)' must be a `var`; @Model makes it read-only, change rows with update() or active()")
            }
            let attributes = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
            let columnName = attributes.first { attributeName($0) == "ColumnName" }
                .flatMap { $0.arguments?.as(LabeledExprListSyntax.self)?.first.flatMap { stringLiteral($0.expression) } }
            let type = typeAnnotation.type.trimmedDescription
            fields.append(
                Field(
                    name: name,
                    type: type,
                    column: columnName ?? snakeCased(plainName),
                    storage: storageName(of: identifier.identifier),
                    isOptional: typeAnnotation.type.is(OptionalTypeSyntax.self) || type.hasPrefix("Optional<"),
                    isKey: attributes.contains { attributeName($0) == "Key" },
                    defaultValue: binding.initializer?.value.trimmedDescription
                )
            )
        }
        self.fields = fields
        self.reservedNames = reservedNames

        guard !fields.filter(\.isKey).isEmpty else { throw MacroExpansionErrorMessage("@Model needs at least one @Key property") }
    }
}

/// The prefix of generated names, as in rust-dbkit. Model properties can't use it, so generated names never clash with
/// them.
let reservedPrefix = "__dbkit_"

/// The private storage behind a column: `__dbkit_title` for `title`.
func storageName(of property: TokenSyntax) -> String {
    reservedPrefix + unescapedName(of: property)
}

/// The identifier without the backticks of a raw identifier like `` `default` ``.
func unescapedName(of identifier: TokenSyntax) -> String {
    identifier.identifier?.name ?? identifier.text
}

func attributeName(_ attribute: AttributeSyntax) -> String? {
    attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text
        ?? attribute.attributeName.as(MemberTypeSyntax.self)?.name.text
}

func stringLiteral(_ expression: ExprSyntax) -> String? {
    guard let literal = expression.as(StringLiteralExprSyntax.self), literal.segments.count == 1,
        let segment = literal.segments.first?.as(StringSegmentSyntax.self)
    else { return nil }
    return segment.content.text
}

/// `userID` → `user_id`, `HTTPWebhook` → `http_webhook`.
func snakeCased(_ name: String) -> String {
    let characters = Array(name)
    var result = ""
    for (index, character) in characters.enumerated() {
        if character.isUppercase, index > 0 {
            let previous = characters[index - 1]
            let nextIsLower = index + 1 < characters.count && characters[index + 1].isLowercase
            if previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLower) { result.append("_") }
        }
        result += character.lowercased()
    }
    return result
}
