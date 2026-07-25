import SwiftUI
import AppKit
import YWRTheme
import YWRMenuUI

/// Makes the process a menu-bar accessory app (no Dock icon) so the
/// `MenuBarExtra` item actually appears — important when launched as a bare
/// `swift run` executable without an app bundle / LSUIElement.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Menu-bar app entry point. Colors/fonts come from an external JSON file when
/// present (see YWRTheme); otherwise the built-in default is used. All UI and
/// state live in the YWRMenuUI library; this target only wires in the concrete,
/// YWRCore-backed `CoreWorkspaceActions`.
@main
struct YwrMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let theme: Theme
    @StateObject private var viewModel: MenuViewModel

    init() {
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
