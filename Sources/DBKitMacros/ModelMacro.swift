import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Expands `@Model`. Members (column storage, columns, relations, `Insert`, the `Loaded` subclass and relation protocols)
/// go into the class, columns become read-only, relation properties become unavailable, and the `Model` conformance
/// goes into an extension.
public struct ModelMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let model = try ModelDescription(declaration: declaration, attribute: node)
        for name in model.reservedNames {
            let message = "names starting with `\(reservedPrefix)` are reserved for DBKit internals"
            context.diagnose(Diagnostic(node: name, message: MacroExpansionErrorMessage(message)))
        }
        let generator = Generator(model: model)
        let members =
            generator.storage() + [generator.memberwiseInit()] + generator.columns() + generator.relations() + [generator.insertType()]
            + generator.find()
        return members.map { DeclSyntax(stringLiteral: $0) }
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let variable = member.as(VariableDeclSyntax.self), variable.bindingSpecifier.text == "var",
            variable.bindings.count == 1, let binding = variable.bindings.first, binding.accessorBlock == nil,
            binding.typeAnnotation != nil,
            let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
            !variable.modifiers.contains(where: { ["static", "class", "private"].contains($0.name.text) })
        else { return [] }
        let isRelation = variable.attributes.contains {
            $0.as(AttributeSyntax.self).flatMap(attributeName).map(ModelDescription.relationAttributes.contains) ?? false
        }
        guard isRelation else { return ["@DBKit._Column"] }
        return [
            "@available(*, unavailable, message: \"relation '\(raw: name)' is not loaded; add .with(\\\\.\(raw: name)) to the query\")"
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // The member expansion reports parse errors; don't report them twice.
        guard let model = try? ModelDescription(declaration: declaration, attribute: node) else { return [] }
        return [DeclSyntax(stringLiteral: Generator(model: model).conformance(for: type.trimmedDescription)).cast(ExtensionDeclSyntax.self)]
    }
}

/// Expands `@_Extension(code)` to `extension <attached type><code>`.
public struct ExtensionCodeMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let code = node.arguments?.as(LabeledExprListSyntax.self)?.first.flatMap({ stringLiteral($0.expression) }) else {
            throw MacroExpansionErrorMessage("@_Extension needs a string literal")
        }
        return [DeclSyntax(stringLiteral: "extension \(type.trimmedDescription)\(code)").cast(ExtensionDeclSyntax.self)]
    }
}

/// Makes a column read-only, backed by the storage `@Model` adds. The init accessor keeps `var x: T = value` valid;
/// the generated initializer writes the storage directly.
public struct ColumnMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let name = declaration.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier
        else { return [] }
        let storage = storageName(of: name)
        return [
            """
            @storageRestrictions(initializes: \(raw: storage))
            init(initialValue) {
                \(raw: storage) = initialValue
            }
            """,
            "get { \(raw: storage) }",
        ]
    }
}

/// Relation properties are unavailable on the plain model, so their getter never runs.
public struct RelationMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        ["get { fatalError(\"unreachable: relation properties are unavailable on the plain model\") }"]
    }
}

private struct Generator {
    let model: ModelDescription
    var access: String { model.access }
    var name: String { model.name }

    /// Mutable only so a Swift default and the initializer can both write it; nothing writes it after `init`.
    func storage() -> [String] {
        model.fields.map { "private var \($0.storage): \($0.type)" }
    }

    func memberwiseInit() -> String {
        """
        \(access)init(\(model.fields.map { parameter($0) }.joined(separator: ", "))) {
            \(model.fields.map { "\($0.storage) = \($0.name)" }.joined(separator: "\n"))
        }
        """
    }

    func columns() -> [String] {
        model.fields.map { field in
            """
            \(access)static var \(field.name): DBKit.Column<\(name), \(field.type)> {
                DBKit.Column("\(field.column)") { $0.\(field.name) }
            }
            """
        }
    }

    func relations() -> [String] {
        guard !model.relations.isEmpty else { return [] }
        // A nested enum rather than statics on the model: a static `user` would shadow the unavailable instance
        // property and replace its "not loaded" diagnostic.
        let relationsEnum = """
            /// The relations of a plain row, for `.with(\\.relation)`, joins and relation paths.
            \(access)enum Relations {
                \(model.relations.map(baseRelation).joined(separator: "\n\n"))
            }
            """
        return [relationsEnum]
            + model.relations.flatMap { relation in
                [
                    relationType(relation), relationProtocol(relation),
                    "\(access)typealias With\(relation.capitalized) = any \(slot(relation))",
                ]
            } + combinedAliases() + [loadedType()] + inverseHasManyRelations()
    }

    /// For each model this one belongs to, the `@HasMany` pointing back, so that side can omit `key:`. With several
    /// `@BelongsTo` to the same model the inverse is ambiguous, and the helper says to pass `key:`.
    private func inverseHasManyRelations() -> [String] {
        var targets: [String] = []
        var links: [String: [(key: String, references: String)]] = [:]
        for relation in model.relations {
            guard case .belongsTo(let key, let references) = relation.kind else { continue }
            if links[relation.target] == nil { targets.append(relation.target) }
            links[relation.target, default: []].append((key, references))
        }
        return targets.map { target in
            let signature = "static func __inverseHasMany(_ relationName: String, of _: \(target).Type) -> DBKit.Relation"
            guard let link = links[target]!.first, links[target]!.count == 1 else {
                return """
                    @available(*, unavailable, message: "\(name) has several @BelongsTo relations to \(target); pass key: to its @HasMany")
                    \(access)\(signature) { fatalError() }
                    """
            }
            return """
                \(access)\(signature) {
                    .hasMany(relationName, key: \(name).\(link.key), references: \(target).\(link.references))
                }
                """
        }
    }

    /// `UserModel.Relations.organization`: the relation loaded onto a plain row.
    private func baseRelation(_ relation: ModelDescription.RelationField) -> String {
        let others = otherRelations(relation)
        let definition =
            switch relation.kind {
            case .belongsTo(let key, let references):
                "DBKit.Relation.belongsTo(\"\(relation.name)\", key: \(name).\(key), references: \(relation.target).\(references))"
            case .hasMany(let key?, let references):
                "DBKit.Relation.hasMany(\"\(relation.name)\", key: \(relation.target).\(key), references: \(name).\(references))"
            case .hasMany(nil, _):
                "\(relation.target).__inverseHasMany(\"\(relation.name)\", of: \(name).self)"
            case .manyToMany(let through, let from, let to):
                "DBKit.Relation.manyToMany(\"\(relation.name)\", from: \(through).\(from), to: \(through).\(to), sourceKey: \(name).id, targetKey: \(relation.target).id)"
            }
        let notLoaded = others.map { _ in "DBKit.NotLoaded" }
        let othersArgument = others.isEmpty ? "" : ", others: { _ in (\(notLoaded.map { $0 + "()" }.joined(separator: ", "))) }"
        return """
            \(access)static var \(relation.name): \(relation.capitalized)Relation<\(([name] + notLoaded + [relation.target]).joined(separator: ", "))> {
                \(relation.capitalized)Relation(relation: \(definition), plan: .base\(othersArgument))
            }
            """
    }

    private func relationType(_ relation: ModelDescription.RelationField) -> String {
        let others = otherRelations(relation)
        let typeName = relation.capitalized + "Relation"
        let conformance =
            switch relation.kind {
            case .belongsTo: "BelongsToRelation"
            case .hasMany: "HasManyRelation"
            case .manyToMany: "ManyToManyRelation"
            }
        let genericParameters = (["Source: \(name)"] + others.map { "\($0.state): DBKit.RelationState" } + ["Child: DBKit.Model"])
        func type(child: String) -> String { "\(typeName)<\((["Source"] + others.map(\.state) + [child]).joined(separator: ", "))>" }
        let outputArguments = model.relations.map { $0.name == relation.name ? relation.loadedType("Child") : $0.state }
        let othersType = "@Sendable (Source) -> (\(others.map(\.state).joined(separator: ", ")))"
        let othersProperty = others.isEmpty ? "" : "\(access)let others: \(othersType)"
        let othersParameter = others.isEmpty ? "" : ", others: @escaping \(othersType)"
        let othersAssignment = others.isEmpty ? "" : "self.others = others"
        let othersForward = others.isEmpty ? "" : ", others: others"
        let othersBinding =
            switch others.count {
            case 0: ""
            case 1: "let \(others[0].name) = others(source)"
            default: "let (\(others.map(\.name).joined(separator: ", "))) = others(source)"
            }
        let attached = relation.isToOne ? "children.first" : "children"
        let outputValues = model.relations.map { "\($0.name): \($0.name == relation.name ? attached : $0.name)" }
        let nextRoots = [
            ("KeyPath<Child.Relations.Type, Next>", "Child.Relations.self", "Child == Child.Base"),
            ("KeyPath<Child.LoadedRelations.Type, Next>", "Child.LoadedRelations.self", "Child: DBKit.LoadedModel"),
        ]
        let nestedLoads = nextRoots.map { keyPath, root, constraint in
            """
            \(access)func with<Next: DBKit.RelationLoad>(
                _ relation: \(keyPath),
                _ strategy: DBKit.LoadStrategy = .selectIn
            ) -> \(type(child: "Next.Output")) where \(constraint), Next.Source == Child {
                \(type(child: "Next.Output"))(relation: self.relation, plan: plan.adding(\(root)[keyPath: relation], strategy)\(othersForward))
            }

            \(access)func with<Next: DBKit.RelationLoad, Nested: DBKit.RelationLoad>(
                _ relation: \(keyPath),
                _ strategy: DBKit.LoadStrategy = .selectIn,
                _ nested: (Next) -> Nested
            ) -> \(type(child: "Nested.Output")) where \(constraint), Nested.Source == Child {
                \(type(child: "Nested.Output"))(relation: self.relation, plan: plan.adding(nested(\(root)[keyPath: relation]), strategy)\(othersForward))
            }
            """
        }
        return """
            \(access)struct \(typeName)<\(genericParameters.joined(separator: ", "))>: DBKit.\(conformance) where Child.Base == \(relation.target) {
                \(access)typealias Target = \(relation.target)
                \(access)typealias Output = \(name).Loaded<\(outputArguments.joined(separator: ", "))>
                \(access)var relation: DBKit.Relation
                \(access)let plan: DBKit.LoadPlan<Child>
                \(othersProperty)

                \(access)init(relation: DBKit.Relation, plan: DBKit.LoadPlan<Child>\(othersParameter)) {
                    self.relation = relation
                    self.plan = plan
                    \(othersAssignment)
                }

                \(access)func attach(_ children: [Child], to source: Source) -> Output {
                    \(othersBinding)
                    return Output(copying: source, \(outputValues.joined(separator: ", ")))
                }

                \(nestedLoads.joined(separator: "\n\n"))
            }
            """
    }

    /// The protocol behind `WithOrganization`, exposing the loaded relation under its own name.
    private func relationProtocol(_ relation: ModelDescription.RelationField) -> String {
        let accessor =
            relation.isToOne
            ? "where \(relation.state): DBKit.LoadedToOne, \(relation.state).Row: \(relation.target) { \(access)var \(relation.name): \(relation.state).Row? { \(relation.storage).row } }"
            : "where \(relation.state): DBKit.LoadedToMany, \(relation.state).Row: \(relation.target) { \(access)var \(relation.name): [\(relation.state).Row] { \(relation.storage).rows } }"
        return """
            @DBKit._Extension(" \(accessor)")
            \(access)protocol _\(relation.capitalized)Slot<\(relation.state)>: \(name) {
                associatedtype \(relation.state): DBKit.RelationState
                var \(relation.storage): \(relation.state) { get }
            }
            """
    }

    /// `WithOrganizationAndTodos` for every combination of up to four relations.
    private func combinedAliases() -> [String] {
        let relations = model.relations
        guard relations.count >= 2, relations.count <= 4 else { return [] }
        return (1..<(1 << relations.count)).compactMap { mask in
            let subset = relations.indices.filter { mask & (1 << $0) != 0 }.map { relations[$0] }
            guard subset.count >= 2 else { return nil }
            return
                "\(access)typealias With\(subset.map(\.capitalized).joined(separator: "And")) = any \(subset.map(slot).joined(separator: " & "))"
        }
    }

    /// The subclass for rows with loaded relations, generic over each relation's state.
    private func loadedType() -> String {
        let relations = model.relations
        let parameters = relations.map { "\($0.state): DBKit.RelationState" }
        let conformances = ["\(name)", "DBKit.LoadedModel"] + relations.map { "_\($0.capitalized)Slot" } + ["@unchecked Sendable"]
        let loadedRelations = relations.map { relation in
            let others = otherRelations(relation)
            let othersArgument =
                switch others.count {
                case 0: ""
                case 1: ", others: { $0.\(others[0].storage) }"
                default: ", others: { (\(others.map { "$0.\($0.storage)" }.joined(separator: ", "))) }"
                }
            return """
                \(access)static var \(relation.name): \(relation.capitalized)Relation<\((["Loaded"] + others.map(\.state) + [relation.target]).joined(separator: ", "))> {
                    \(relation.capitalized)Relation(relation: \(name).Relations.\(relation.name).relation, plan: .base\(othersArgument))
                }
                """
        }
        return """
            /// A row with loaded relations. `.with(_:)` creates it; pass it wherever \(name) is expected.
            \(access)final class Loaded<\(parameters.joined(separator: ", "))>: \(conformances.joined(separator: ", ")) {
                \(relations.map { "\(access)let \($0.storage): \($0.state)" }.joined(separator: "\n"))

                \(access)init(copying source: \(name), \(relations.map { "\($0.name): \($0.state)" }.joined(separator: ", "))) {
                    \(relations.map { "\($0.storage) = \($0.name)" }.joined(separator: "\n"))
                    super.init(\(model.fields.map { "\($0.name): source.\($0.name)" }.joined(separator: ", ")))
                }

                /// The relations `.with(_:)` can add to a loaded row, keeping the ones already loaded.
                \(access)enum LoadedRelations {
                    \(loadedRelations.joined(separator: "\n\n"))
                }
            }
            """
    }

    func insertType() -> String {
        let fields = model.fields.filter { !$0.isAutoIncrement }
        let values = fields.map { field in
            field.isDatabaseDefault
                ? "\(field.name).map { DBKit.ColumnValue(\"\(field.column)\", $0) } ?? .databaseDefault(\"\(field.column)\")"
                : "DBKit.ColumnValue(\"\(field.column)\", \(field.name))"
        }
        return """
            \(access)struct Insert: DBKit.ModelInsert {
                \(fields.map { "\(access)var \($0.name): \(insertType($0))" }.joined(separator: "\n"))

                \(access)init(\(fields.map { parameter($0, inInsert: true) }.joined(separator: ", "))) {
                    \(fields.map { "self.\($0.name) = \($0.name)" }.joined(separator: "\n"))
                }

                \(access)var columnValues: [DBKit.ColumnValue] {
                    [\(values.joined(separator: ", "))]
                }
            }
            """
    }

    func find() -> [String] {
        guard model.keys.count == 1, let key = model.keys.first else { return [] }
        return [
            """
            /// Fetches the row with this primary key.
            \(access)static func find(_ \(key.name): \(key.type), on executor: some DBKit.DatabaseExecutor) async throws -> \(name)? {
                try await \(name).query().filter(\(name).\(key.name) == \(key.name)).first(on: executor)
            }
            """
        ]
    }

    func conformance(for type: String) -> String {
        let decodeArguments = model.fields.map { "\($0.name): try row.decode((\($0.type)).self, \"\($0.column)\")" }
        let keyPaths = model.fields.map { "\\.\($0.name): \"\($0.column)\"" }
        let columnValues = model.fields.map { "DBKit.ColumnValue(\"\($0.column)\", \($0.name))" }
        return """
            extension \(type): DBKit.Model, @unchecked Sendable {
                \(access)typealias Base = \(name)

                \(access)static var schema: DBKit.Schema {
                    DBKit.Schema(
                        table: "\(model.table)",
                        tableSchema: \(model.schema.map { "\"\($0)\"" } ?? "nil"),
                        columns: [\(model.fields.map { "\"\($0.column)\"" }.joined(separator: ", "))],
                        primaryKey: [\(model.keys.map { "\"\($0.column)\"" }.joined(separator: ", "))]
                    )
                }

                \(access)static func decodeBase(from row: DBKit.RowReader) throws -> \(name) {
                    \(name)(\(decodeArguments.joined(separator: ", ")))
                }

                \(access)static func columnName(for keyPath: PartialKeyPath<\(name)>) -> String? {
                    let columns: [PartialKeyPath<\(name)>: String] = [\(keyPaths.joined(separator: ", "))]
                    return columns[keyPath]
                }

                \(access)var base: \(name) { self }

                \(access)var columnValues: [DBKit.ColumnValue] {
                    [\(columnValues.joined(separator: ", "))]
                }
            }
            """
    }

    private func otherRelations(_ relation: ModelDescription.RelationField) -> [ModelDescription.RelationField] {
        model.relations.filter { $0.name != relation.name }
    }

    private func slot(_ relation: ModelDescription.RelationField) -> String {
        "_\(relation.capitalized)Slot<\(relation.loadedType(relation.target))>"
    }

    private func insertType(_ field: ModelDescription.Field) -> String {
        field.isDatabaseDefault ? "\(field.type)?" : field.type
    }

    private func parameter(_ field: ModelDescription.Field, inInsert: Bool = false) -> String {
        if inInsert, field.isDatabaseDefault { return "\(field.name): \(field.type)? = nil" }
        return "\(field.name): \(field.type)" + (field.parameterDefault.map { " = \($0)" } ?? "")
    }
}
