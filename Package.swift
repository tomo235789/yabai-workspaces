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
        .executable(name: "ywr-shot", targets: ["ywr-shot"]),
        .library(name: "YWRCore", targets: ["YWRCore"]),
        .library(name: "YWRTheme", targets: ["YWRTheme"]),
        .library(name: "YWRMenuUI", targets: ["YWRMenuUI"])
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
        // Menu-bar UI as a library: views, view model, theme mapping, and a
        // headless renderer. Separated from the app entry point so the UI is
        // unit-testable and can be rendered to PNG without a GUI session.
        .target(
            name: "YWRMenuUI",
            dependencies: ["YWRTheme"],
            path: "Sources/YWRMenuUI"
        ),
        // SwiftUI menu-bar app entry point + YWRCore-backed actions.
        .executableTarget(
            name: "ywr-menubar",
            dependencies: ["YWRCore", "YWRTheme", "YWRMenuUI"],
            path: "Sources/ywr-menubar"
        ),
        // Headless screenshot tool: renders the menu UI to PNG files.
        .executableTarget(
            name: "ywr-shot",
            dependencies: ["YWRTheme", "YWRMenuUI"],
            path: "Sources/ywr-shot"
        ),
        .testTarget(
            name: "YWRCoreTests",
            dependencies: ["YWRCore", "YWRTheme"],
            path: "Tests/YWRCoreTests"
        ),
        .testTarget(
            name: "YWRMenuUITests",
            dependencies: ["YWRMenuUI", "YWRTheme"],
            path: "Tests/YWRMenuUITests"
        )
    ]
)
