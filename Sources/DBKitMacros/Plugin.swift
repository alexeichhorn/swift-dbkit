import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct DBKitMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        ModelMacro.self, MarkerMacro.self, RelationMacro.self, ColumnMacro.self, ExtensionCodeMacro.self, DatabaseEnumMacro.self,
        ProjectionMacro.self,
    ]
}

/// Field markers like `@Key` and `@BelongsTo` generate nothing themselves; `@Model` reads them.
public struct MarkerMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
