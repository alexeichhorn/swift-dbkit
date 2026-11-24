import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Expands `@Model`. Members (column storage, the initializer, the columns, `Insert` and `find`) go into the class,
/// columns become read-only, and the `Model` conformance goes into an extension.
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
        let members = generator.storage() + [generator.memberwiseInit()] + generator.columns() + [generator.insertType()] + generator.find()
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
            binding.typeAnnotation != nil, binding.pattern.is(IdentifierPatternSyntax.self),
            !variable.modifiers.contains(where: { ["static", "class", "private"].contains($0.name.text) })
        else { return [] }
        return ["@DBKit._Column"]
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
                DBKit.Column("\(field.column)")
            }
            """
        }
    }

    func insertType() -> String {
        let fields = model.fields.filter { !$0.isAutoIncrement }
        return """
            \(access)struct Insert: DBKit.ModelInsert {
                \(fields.map { "\(access)var \($0.name): \($0.type)" }.joined(separator: "\n"))

                \(access)init(\(fields.map { parameter($0) }.joined(separator: ", "))) {
                    \(fields.map { "self.\($0.name) = \($0.name)" }.joined(separator: "\n"))
                }

                \(access)var columnValues: [DBKit.ColumnValue] {
                    [\(fields.map { "DBKit.ColumnValue(\"\($0.column)\", \($0.name))" }.joined(separator: ", "))]
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
        let columnValues = model.fields.map { "DBKit.ColumnValue(\"\($0.column)\", \($0.name))" }
        return """
            extension \(type): DBKit.Model, @unchecked Sendable {
                \(access)typealias Base = \(name)

                \(access)static var schema: DBKit.Schema {
                    DBKit.Schema(
                        table: "\(model.table)",
                        columns: [\(model.fields.map { "\"\($0.column)\"" }.joined(separator: ", "))],
                        primaryKey: [\(model.keys.map { "\"\($0.column)\"" }.joined(separator: ", "))]
                    )
                }

                \(access)static func decodeBase(from row: DBKit.RowReader) throws -> \(name) {
                    \(name)(\(decodeArguments.joined(separator: ", ")))
                }

                \(access)var columnValues: [DBKit.ColumnValue] {
                    [\(columnValues.joined(separator: ", "))]
                }
            }
            """
    }

    private func parameter(_ field: ModelDescription.Field) -> String {
        "\(field.name): \(field.type)" + (field.parameterDefault.map { " = \($0)" } ?? "")
    }
}
