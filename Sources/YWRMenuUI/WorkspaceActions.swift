import Foundation

/// What the menu-bar UI can ask the app to do. Async and Sendable so the heavy
/// work (subprocess calls, waiting for launched apps) runs OFF the main actor —
/// tapping a button must never freeze the menu. Concrete implementations live
/// in the app target (Dependency Inversion).
public protocol WorkspaceActions: Sendable {
    func snapshotNames() async -> [String]
    func save(name: String) async throws
    func restoreAuto() async throws -> String
}

/// Fixed, side-effect-free actions for SwiftUI previews and headless rendering.
public struct StubActions: WorkspaceActions {
    private let names: [String]
    private let restoreResult: String

    public init(names: [String] = [], restoreResult: String = "Ready") {
        self.names = names
        self.restoreResult = restoreResult
    }

    public func snapshotNames() async -> [String] { names }
    public func save(name: String) async throws {}
    public func restoreAuto() async throws -> String { restoreResult }
}
