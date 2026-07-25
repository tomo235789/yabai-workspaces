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

        let hosting = NSHostingController(rootView: MenuContentView(model: viewModel, theme: theme))
        hosting.sizingOptions = [.preferredContentSize]   // size the popover to fit the whole UI (incl. Quit)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = hosting
        self.popover = popover

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "yabai workspaces") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "ywr"   // fallback so the item is never zero-width
            }
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }

    @objc private func handleClick() {
        // Right-click shows a Quit menu; left-click toggles the popover.
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit yabai workspaces", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
