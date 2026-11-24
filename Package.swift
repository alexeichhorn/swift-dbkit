// swift-tools-version:6.4
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
    ],
    targets: [
        .target(
            name: "DBKit",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio")
            ]
        ),
        .testTarget(
            name: "DBKitTests",
            dependencies: ["DBKit"]
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
