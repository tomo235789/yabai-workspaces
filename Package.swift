// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "yabai-workspaces",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ywr", targets: ["ywr"]),
        .executable(name: "ywr-menubar", targets: ["ywr-menubar"]),
        .library(name: "YWRCore", targets: ["YWRCore"]),
        .library(name: "YWRTheme", targets: ["YWRTheme"])
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
        // Theming schema + loader. Foundation-only (no SwiftUI) so colors/fonts
        // can be specified in an external JSON file and unit-tested.
        .target(
            name: "YWRTheme",
            path: "Sources/YWRTheme"
        ),
        // SwiftUI menu-bar app. Maps the theme to SwiftUI and drives YWRCore.
        .executableTarget(
            name: "ywr-menubar",
            dependencies: ["YWRCore", "YWRTheme"],
            path: "Sources/ywr-menubar"
        ),
        .testTarget(
            name: "YWRCoreTests",
            dependencies: ["YWRCore", "YWRTheme"],
            path: "Tests/YWRCoreTests"
        )
    ]
)
