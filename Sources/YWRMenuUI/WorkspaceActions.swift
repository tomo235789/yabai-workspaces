import Foundation

/// What the menu-bar UI can ask the app to do. Async and Sendable so the heavy
/// work (subprocess calls, waiting for launched apps) runs OFF the main actor —
/// tapping a button must never freeze the menu. Concrete implementations live
/// in the app target (Dependency Inversion).
public protocol WorkspaceActions: Sendable {
    func snapshotNames() async -> [String]
    func save(name: String) async throws
    func restore(name: String) async throws -> String
    /// Restore across every desktop (Space), switching through them — the
    /// heavier "all desktops" path, kept separate from the quick current-desktop
    /// restore since it flips the screen.
    func restoreAcrossDesktops(name: String) async throws -> String
    func restoreAuto() async throws -> String
    func delete(name: String) async throws
}

/// Fixed, side-effect-free actions for SwiftUI previews and headless rendering.
public struct StubActions: WorkspaceActions {
    private let names: [String]
    private let restoreResult: String

    public init(names: [String] = [], restoreResult: String = "Ready") {
        self.names = names
        self.restoreResult = restoreResult
    }

    public func snapshotNames() async -> [String] {
        names
    }

    public func save(name _: String) async throws {}
    public func restore(name _: String) async throws -> String {
        restoreResult
    }

    public func restoreAcrossDesktops(name _: String) async throws -> String {
        restoreResult
    }

    public func restoreAuto() async throws -> String {
        restoreResult
    }

    public func delete(name _: String) async throws {}
}
