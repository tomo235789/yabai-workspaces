import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI
import YWRMenuUI
import YWRTheme

// Pure-AppKit menu-bar app: a classic NSStatusItem + NSPopover is the most
// reliable way to show a menu-bar icon (SwiftUI's MenuBarExtra didn't render an
// icon here). The popover hosts the shared SwiftUI `MenuContentView`.
// `.accessory` keeps the app out of the Dock.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_: Notification) {
        requestPermissions()

        let theme = Theme(ThemeLoader(url: CoreWorkspaceActions.themeConfigURL()).load())
        let viewModel = MenuViewModel(actions: CoreWorkspaceActions())

        let hosting = NSHostingController(rootView: MenuContentView(model: viewModel, theme: theme))
        hosting.sizingOptions = [.preferredContentSize] // size the popover to fit the whole UI (incl. Quit)

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
                button.title = "ywr" // fallback so the item is never zero-width
            }
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    /// Requests the permissions the native backend needs — but ONLY the ones not
    /// already granted, so an already-configured setup shows no prompt at all.
    /// Preflighting first also keeps the app from re-registering / re-prompting on
    /// every launch once the user has granted access in System Settings.
    private func requestPermissions() {
        // Accessibility (required to move/resize windows). Already trusted → do
        // nothing; otherwise the prompt option shows the dialog and adds the app
        // to the Accessibility list. The key is spelled out to avoid the
        // non-Sendable global under Swift 6.
        if !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        // Screen Recording (optional: improves window-title matching). Preflight
        // so we never prompt when it's already granted.
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
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
