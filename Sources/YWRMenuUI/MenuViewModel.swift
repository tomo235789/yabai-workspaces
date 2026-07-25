import Foundation

/// Observable state for the menu-bar UI. Methods are `async` so the View drives
/// them from a `Task`, keeping the main actor free while YWRCore work runs; the
/// `@Published` updates then land back on the main actor. The seeding init lets
/// previews, the renderer, and tests set a deterministic state.
@MainActor
public final class MenuViewModel: ObservableObject {
    @Published public private(set) var snapshots: [String]
    @Published public private(set) var status: String
    @Published public private(set) var isBusy: Bool = false
    @Published public var newName: String

    private let actions: any WorkspaceActions

    public init(
        actions: any WorkspaceActions,
        snapshots: [String] = [],
        status: String = "",
        newName: String = ""
    ) {
        self.actions = actions
        self.snapshots = snapshots
        self.status = status
        self.newName = newName
    }

    public func refresh() async {
        snapshots = await actions.snapshotNames()
    }

    public func save() async {
        guard !isBusy else { return }   // ignore re-entrant taps while working
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "Enter a name"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await actions.save(name: trimmed)
            status = "Saved '\(trimmed)'"
            newName = ""
            snapshots = await actions.snapshotNames()
        } catch {
            status = "Save failed: \(error)"
        }
    }

    public func restore(name: String) async {
        guard !isBusy else { return }   // ignore re-entrant taps while working
        isBusy = true
        defer { isBusy = false }
        do {
            status = try await actions.restore(name: name)
        } catch {
            status = "Restore failed: \(error)"
        }
    }

    /// Restore across every desktop (walks Spaces). Heavier than `restore`, so
    /// it's a separate action the user opts into.
    public func restoreAcrossDesktops(name: String) async {
        guard !isBusy else { return }   // ignore re-entrant taps while working
        isBusy = true
        defer { isBusy = false }
        do {
            status = try await actions.restoreAcrossDesktops(name: name)
        } catch {
            status = "Restore failed: \(error)"
        }
    }

    public func restoreAuto() async {
        guard !isBusy else { return }   // ignore re-entrant taps while working
        isBusy = true
        defer { isBusy = false }
        do {
            status = try await actions.restoreAuto()
        } catch {
            status = "Restore failed: \(error)"
        }
    }

    /// Re-save the current layout into an existing snapshot name — the one-click
    /// "overwrite" path so you don't have to retype the name into the field.
    public func overwrite(name: String) async {
        guard !isBusy else { return }   // ignore re-entrant taps while working
        isBusy = true
        defer { isBusy = false }
        do {
            try await actions.save(name: name)
            status = "Updated '\(name)'"
            snapshots = await actions.snapshotNames()
        } catch {
            status = "Save failed: \(error)"
        }
    }

    public func delete(name: String) async {
        guard !isBusy else { return }   // ignore re-entrant taps while working
        isBusy = true
        defer { isBusy = false }
        do {
            try await actions.delete(name: name)
            status = "Deleted '\(name)'"
            snapshots = await actions.snapshotNames()
        } catch {
            status = "Delete failed: \(error)"
        }
    }
}
