// swift-tools-version:6.4
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-dbkit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DBKit", targets: ["DBKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
    ],
    targets: [
        .macro(
            name: "DBKitMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "DBKit",
            dependencies: [
                "DBKitMacros",
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
        .testTarget(
            name: "DBKitTests",
            dependencies: ["DBKit", .product(name: "ServiceLifecycle", package: "swift-service-lifecycle")]
        ),
        .testTarget(
            name: "DBKitMacrosTests",
            dependencies: [
                "DBKitMacros",
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
