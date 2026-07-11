// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "yabai-workspaces",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ywr", targets: ["ywr"]),
        .library(name: "YWRCore", targets: ["YWRCore"])
    ],
    targets: [
        // Executable: thin CLI layer that wires the core together.
        .executableTarget(
            name: "ywr",
            dependencies: ["YWRCore"],
            path: "Sources/ywr"
        ),
        // Library: all domain logic, kept free of process/argv concerns so it
        // can be unit tested with injected fakes (Dependency Inversion).
        .target(
            name: "YWRCore",
            path: "Sources/YWRCore"
        ),
        .testTarget(
            name: "YWRCoreTests",
            dependencies: ["YWRCore"],
            path: "Tests/YWRCoreTests"
        )
    ]
)
