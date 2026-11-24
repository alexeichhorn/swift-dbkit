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
        let isAutoIncrement: Bool
        /// The Swift default from `var x: T = value`, used by the initializers and `Insert`.
        let defaultValue: String?

        /// The default parameter value in the initializers.
        var parameterDefault: String? { defaultValue ?? (isOptional ? "nil" : nil) }
    }

    struct RelationField {
        enum Kind {
            case belongsTo(key: String, references: String)
            /// `key` is `nil` when it comes from the target's `@BelongsTo` back to this model.
            case hasMany(key: String?, references: String)
            case manyToMany(through: String, from: String, to: String)
        }

        let name: String
        /// The loaded relation on `Loaded`, see ``storageName(of:)``.
        let storage: String
        let kind: Kind
        let target: String

        var isToOne: Bool {
            if case .belongsTo = kind { return true }
            return false
        }

        /// `organization` → `Organization`, the stem of the generated names.
        var capitalized: String { name.prefix(1).uppercased() + name.dropFirst() }
        /// The `Loaded` generic parameter holding this relation's state.
        var state: String { capitalized + "State" }
        /// The relation's loaded type with `row` as its target: `UserModel?` or `[TodoModel]`.
        func loadedType(_ row: String) -> String { isToOne ? "\(row)?" : "[\(row)]" }
    }

    static let relationAttributes = ["BelongsTo", "HasMany", "ManyToMany"]

    let name: String
    let access: String
    let table: String
    let fields: [Field]
    let relations: [RelationField]
    /// Property names that use ``reservedPrefix``. The member expansion reports them but still generates the model, so
    /// the compiler adds no follow-up errors.
    let reservedNames: [TokenSyntax]

    var keys: [Field] { fields.filter(\.isKey) }

    init(declaration: some DeclGroupSyntax, attribute: AttributeSyntax) throws {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw MacroExpansionErrorMessage(
                "@Model must be applied to a class, so rows with loaded relations can be passed where the plain model is expected")
        }
        guard !classDecl.modifiers.contains(where: { $0.name.text == "final" }) else {
            throw MacroExpansionErrorMessage("@Model classes can't be final: rows with loaded relations are a generated subclass")
        }
        guard classDecl.genericParameterClause == nil else {
            throw MacroExpansionErrorMessage("@Model classes can't be generic; declare relations as properties of their loaded type")
        }
        name = classDecl.name.text
        access =
            classDecl.modifiers.first { ["public", "package"].contains($0.name.text) }.map { $0.name.text + " " } ?? ""

        let tableArgument = attribute.arguments?.as(LabeledExprListSyntax.self)?.first { $0.label?.text == "table" }
        table = tableArgument.flatMap { stringLiteral($0.expression) } ?? snakeCased(name)

        var fields: [Field] = []
        var relations: [RelationField] = []
        var reservedNames: [TokenSyntax] = []
        for member in classDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }),
                let binding = variable.bindings.first
            else { continue }
            let attributes = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
            let isRelation = attributes.contains { attributeName($0).map(Self.relationAttributes.contains) ?? false }
            // Computed properties are the model's own helpers.
            if binding.accessorBlock != nil, !isRelation { continue }
            if variable.modifiers.contains(where: { $0.name.text == "private" }) { continue }
            guard variable.bindings.count == 1, let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                let typeAnnotation = binding.typeAnnotation
            else {
                throw MacroExpansionErrorMessage("@Model properties need one name and an explicit type")
            }
            let name = identifier.identifier.text
            let plainName = unescapedName(of: identifier.identifier)
            if plainName.hasPrefix(reservedPrefix) { reservedNames.append(identifier.identifier) }

            if isRelation {
                guard variable.bindingSpecifier.text == "var" else {
                    throw MacroExpansionErrorMessage("relation '\(name)' must be a `var`; it's generated as an accessor")
                }
                relations.append(
                    try Self.relation(
                        named: name, storage: storageName(of: identifier.identifier), type: typeAnnotation.type, attributes: attributes))
                continue
            }
            guard variable.bindingSpecifier.text == "var" else {
                throw MacroExpansionErrorMessage(
                    "column '\(name)' must be a `var`; @Model makes it read-only, change rows with update() or active()")
            }
            let columnName = attributes.first { attributeName($0) == "ColumnName" }
                .flatMap { $0.arguments?.as(LabeledExprListSyntax.self)?.first.flatMap { stringLiteral($0.expression) } }
            let type = typeAnnotation.type.trimmedDescription
            let isAutoIncrement = attributes.contains { attributeName($0) == "AutoIncrement" }
            if isAutoIncrement, binding.initializer != nil {
                throw MacroExpansionErrorMessage(
                    "@AutoIncrement column '\(name)' can't have a Swift default; the database assigns the value")
            }
            fields.append(
                Field(
                    name: name,
                    type: type,
                    column: columnName ?? snakeCased(plainName),
                    storage: storageName(of: identifier.identifier),
                    isOptional: typeAnnotation.type.is(OptionalTypeSyntax.self) || type.hasPrefix("Optional<"),
                    isKey: attributes.contains { attributeName($0) == "Key" },
                    isAutoIncrement: isAutoIncrement,
                    defaultValue: binding.initializer?.value.trimmedDescription
                )
            )
        }
        self.fields = fields
        self.relations = relations
        self.reservedNames = reservedNames

        guard !fields.filter(\.isKey).isEmpty else { throw MacroExpansionErrorMessage("@Model needs at least one @Key property") }
    }

    private static func relation(named name: String, storage: String, type: TypeSyntax, attributes: [AttributeSyntax]) throws
        -> RelationField
    {
        let attribute = attributes.first { attributeName($0).map(relationAttributes.contains) ?? false }!
        let kind = attributeName(attribute)!
        let arguments = Array(attribute.arguments?.as(LabeledExprListSyntax.self) ?? [])
        func string(_ label: String, default value: String? = nil) throws -> String {
            if let argument = arguments.first(where: { $0.label?.text == label }), let string = stringLiteral(argument.expression) {
                return string
            }
            if let value { return value }
            throw MacroExpansionErrorMessage("@\(kind) on '\(name)' needs a string literal `\(label):` argument")
        }

        let target: String
        if kind == "BelongsTo" {
            guard let optional = type.as(OptionalTypeSyntax.self) else {
                throw MacroExpansionErrorMessage("@BelongsTo relation '\(name)' must have an optional model type, e.g. `UserModel?`")
            }
            target = optional.wrappedType.trimmedDescription
        } else {
            guard let array = type.as(ArrayTypeSyntax.self) else {
                throw MacroExpansionErrorMessage("@\(kind) relation '\(name)' must have an array type, e.g. `[TodoModel]`")
            }
            target = array.element.trimmedDescription
        }

        let relationKind: RelationField.Kind =
            switch kind {
            case "BelongsTo": .belongsTo(key: try string("key"), references: try string("references", default: "id"))
            case "HasMany":
                if arguments.contains(where: { $0.label?.text == "key" }) {
                    .hasMany(key: try string("key"), references: try string("references", default: "id"))
                } else if arguments.contains(where: { $0.label?.text == "references" }) {
                    throw MacroExpansionErrorMessage("@HasMany on '\(name)' needs `key:` when it sets `references:`")
                } else {
                    .hasMany(key: nil, references: "id")
                }
            default:
                .manyToMany(
                    through: try modelType(arguments.first { $0.label?.text == "through" }, relation: name), from: try string("from"),
                    to: try string("to"))
            }
        return RelationField(name: name, storage: storage, kind: relationKind, target: target)
    }

    private static func modelType(_ argument: LabeledExprSyntax?, relation: String) throws -> String {
        guard let member = argument?.expression.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "self",
            let base = member.base
        else { throw MacroExpansionErrorMessage("@ManyToMany on '\(relation)' needs a join model like `through: TodoTagModel.self`") }
        return base.trimmedDescription
    }
}

/// The prefix of generated names, as in rust-dbkit. Model properties can't use it, so generated names never clash with
/// them.
let reservedPrefix = "__dbkit_"

/// The storage behind a property: the private storage of column `title` is `__dbkit_title`, and a loaded relation
/// `user` is `__dbkit_user` on `Loaded`.
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
