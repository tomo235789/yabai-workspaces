import SwiftUI
import YWRTheme

// Implemented via ollama gemma4:31b, reviewed and integrated. Adjustment:
//   - the App falls back to the real `CoreWorkspaceActions` (not PreviewActions)
//     so the shipped menu bar drives YWRCore; PreviewActions stays for previews.

// Async and Sendable so the heavy work (subprocess calls, waiting for launched
// apps) runs OFF the main actor — tapping a button must never freeze the menu.
public protocol WorkspaceActions: Sendable {
    func snapshotNames() async -> [String]
    func save(name: String) async throws
    func restoreAuto() async throws -> String
}

@MainActor
public final class MenuViewModel: ObservableObject {
    @Published public private(set) var snapshots: [String] = []
    @Published public private(set) var status: String = ""
    @Published public private(set) var isBusy: Bool = false
    @Published public var newName: String = ""

    private let actions: any WorkspaceActions

    public init(actions: any WorkspaceActions) {
        self.actions = actions
    }

    public func refresh() {
        Task { snapshots = await actions.snapshotNames() }
    }

    public func save() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "Enter a name"
            return
        }
        Task {
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
    }

    public func restoreAuto() {
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                status = try await actions.restoreAuto()
            } catch {
                status = "Restore failed: \(error)"
            }
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var model: MenuViewModel
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("yabai workspaces")
                .font(theme.titleFont)
                .foregroundColor(theme.textPrimary)

            HStack {
                TextField("snapshot name", text: $model.newName)
                    .textFieldStyle(.roundedBorder)
                    .font(theme.bodyFont)

                Button("Save") {
                    model.save()
                }
                .buttonStyle(.borderedProminent)
                .font(theme.bodyFont)
                .disabled(model.isBusy)
            }

            Button("Restore (auto)") {
                model.restoreAuto()
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
            .font(theme.bodyFont)
            .disabled(model.isBusy)

            if !model.snapshots.isEmpty {
                Text("Saved:")
                    .font(theme.bodyFont)
                    .foregroundColor(theme.textSecondary)

                ForEach(model.snapshots, id: \.self) { name in
                    Text(name)
                        .font(theme.bodyFont)
                        .foregroundColor(theme.textPrimary)
                }
            }

            if !model.status.isEmpty {
                Text(model.status)
                    .font(theme.bodyFont)
                    .foregroundColor(theme.textSecondary)
                    .italic()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(theme.bodyFont)
            .foregroundColor(theme.error)
        }
        .padding()
        .frame(minWidth: 250)
        .background(theme.background)
        .onAppear {
            model.refresh()
        }
    }
}

/// No-op actions for SwiftUI previews.
struct PreviewActions: WorkspaceActions {
    func snapshotNames() async -> [String] { [] }
    func save(name: String) async throws {}
    func restoreAuto() async throws -> String { "Preview Mode" }
}

@main
struct YwrMenuBarApp: App {
    let theme: Theme
    @StateObject private var viewModel: MenuViewModel

    init() {
        // Colors/fonts come from an external JSON file when present (see
        // Theme+config in YWRTheme); otherwise the built-in default is used.
        let config = ThemeLoader(url: CoreWorkspaceActions.themeConfigURL()).load()
        self.theme = Theme(config)
        _viewModel = StateObject(wrappedValue: MenuViewModel(actions: CoreWorkspaceActions()))
    }

    var body: some Scene {
        MenuBarExtra("ywr", systemImage: "rectangle.3.group") {
            MenuContentView(model: viewModel, theme: theme)
        }
        .menuBarExtraStyle(.window)
    }
}
