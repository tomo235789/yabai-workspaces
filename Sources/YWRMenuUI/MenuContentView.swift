import SwiftUI
import AppKit

/// The menu-bar popover content. Actions are fired inside a `Task` so the async
/// view-model methods run without blocking the main actor.
public struct MenuContentView: View {
    @ObservedObject private var model: MenuViewModel
    private let theme: Theme
    /// SwiftUI's `TextField` doesn't rasterize cleanly through `ImageRenderer`,
    /// so the screenshot tool asks for a static, display-only field instead.
    private let staticField: Bool
    /// Name awaiting delete confirmation (deletion is destructive → confirm first).
    @State private var pendingDelete: String?

    public init(model: MenuViewModel, theme: Theme, staticField: Bool = false) {
        self.model = model
        self.theme = theme
        self.staticField = staticField
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("yabai workspaces")
                .font(theme.titleFont)
                .foregroundColor(theme.textPrimary)

            HStack {
                nameField

                Button("Save") { Task { await model.save() } }
                    .buttonStyle(.borderedProminent)
                    .font(theme.bodyFont)
                    .disabled(model.isBusy)
            }

            Button("Restore (auto)") { Task { await model.restoreAuto() } }
                .buttonStyle(.bordered)
                .tint(theme.accent)
                .font(theme.bodyFont)
                .disabled(model.isBusy)

            if !model.snapshots.isEmpty {
                Text("Saved — click a name to restore, ▦ to restore across all desktops:")
                    .font(theme.bodyFont)
                    .foregroundColor(theme.textSecondary)

                ForEach(model.snapshots, id: \.self) { name in
                    HStack(spacing: 8) {
                        // Clicking the name restores it (the header says so) — no
                        // separate "Restore" label needed.
                        Button { Task { await model.restore(name: name) } } label: {
                            Text(name)
                                .font(theme.bodyFont)
                                .foregroundColor(theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)

                        // Restore across ALL desktops: walks Spaces so windows on
                        // other desktops are placed too (flips the screen). Kept
                        // separate from the quick current-desktop click above.
                        Button { Task { await model.restoreAcrossDesktops(name: name) } } label: {
                            Image(systemName: "square.grid.2x2")
                                .foregroundColor(theme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                        .help("Restore '\(name)' across all desktops")
                        .accessibilityLabel("Restore \(name) across all desktops")

                        // One-click overwrite: re-save the current layout into this
                        // existing name without retyping it into the field.
                        Button { Task { await model.overwrite(name: name) } } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(theme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                        .help("Overwrite '\(name)' with the current layout")
                        .accessibilityLabel("Overwrite \(name) with the current layout")

                        Button { pendingDelete = name } label: {
                            Image(systemName: "trash")
                                .foregroundColor(theme.error)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                        .help("Delete '\(name)'")
                        .accessibilityLabel("Delete \(name)")
                    }
                }
            }

            if !model.status.isEmpty {
                Text(model.status)
                    .font(theme.bodyFont)
                    .foregroundColor(theme.textSecondary)
                    .italic()
            }

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(theme.bodyFont)
                .foregroundColor(theme.error)
        }
        .padding()
        .frame(minWidth: 250)
        .background(theme.background)
        .onAppear { Task { await model.refresh() } }
        .confirmationDialog(
            "Delete snapshot \"\(pendingDelete ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let name = pendingDelete {
                Button("Delete", role: .destructive) { Task { await model.delete(name: name) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var nameField: some View {
        if staticField {
            let empty = model.newName.isEmpty
            Text(empty ? "snapshot name" : model.newName)
                .font(theme.bodyFont)
                .foregroundColor(empty ? theme.textSecondary : theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.textSecondary.opacity(0.4)))
                )
        } else {
            TextField("snapshot name", text: $model.newName)
                .textFieldStyle(.roundedBorder)
                .font(theme.bodyFont)
        }
    }
}
