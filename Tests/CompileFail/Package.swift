// swift-tools-version:6.4
import PackageDescription

// The compile-fail fixtures, built by `CompileFailTests` with the native build system. Whole-module mode reports the
// errors of every file, where the build would otherwise stop at the first failing file. Without a separate
// emit-module job, its one compile job also reports errors in function bodies when declarations have errors.
let package = Package(
    name: "CompileFail",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "Fixtures",
            dependencies: [.product(name: "DBKit", package: "swift-dbkit")],
            swiftSettings: [.unsafeFlags(["-wmo", "-no-emit-module-separately-wmo"])]
        )
    ]
)
