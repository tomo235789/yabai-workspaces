import SwiftUI
import YWRTheme
import YWRMenuUI

/// Menu-bar app entry point. Colors/fonts come from an external JSON file when
/// present (see YWRTheme); otherwise the built-in default is used. All UI and
/// state live in the YWRMenuUI library; this target only wires in the concrete,
/// YWRCore-backed `CoreWorkspaceActions`.
@main
struct YwrMenuBarApp: App {
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
