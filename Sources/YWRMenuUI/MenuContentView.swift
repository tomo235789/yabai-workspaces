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
                Text("Saved — click to restore:")
                    .font(theme.bodyFont)
                    .foregroundColor(theme.textSecondary)

                ForEach(model.snapshots, id: \.self) { name in
                    Button { Task { await model.restore(name: name) } } label: {
                        HStack {
                            Text(name)
                                .font(theme.bodyFont)
                                .foregroundColor(theme.textPrimary)
                            Spacer()
                            Text("Restore")
                                .font(theme.bodyFont)
                                .foregroundColor(theme.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
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
