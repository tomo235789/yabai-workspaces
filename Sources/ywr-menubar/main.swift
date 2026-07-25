import AppKit
import SwiftUI
import YWRTheme
import YWRMenuUI

// Pure-AppKit menu-bar app: a classic NSStatusItem + NSPopover is the most
// reliable way to show a menu-bar icon (SwiftUI's MenuBarExtra didn't render an
// icon here). The popover hosts the shared SwiftUI `MenuContentView`.
// `.accessory` keeps the app out of the Dock.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let theme = Theme(ThemeLoader(url: CoreWorkspaceActions.themeConfigURL()).load())
        let viewModel = MenuViewModel(actions: CoreWorkspaceActions())

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 380)
        popover.contentViewController = NSHostingController(rootView: MenuContentView(model: viewModel, theme: theme))
        self.popover = popover

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "yabai workspaces") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "ywr"   // fallback so the item is never zero-width
            }
            button.action = #selector(togglePopover)
            button.target = self
        }
        self.statusItem = item
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
