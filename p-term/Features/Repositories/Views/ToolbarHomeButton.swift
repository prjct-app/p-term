import SwiftUI

/// Leading toolbar pill that toggles the full-screen Welcome/home view.
/// Rendered at the `ContentView` root (not inside `WorktreeToolbarContent`) so
/// it stays visible whether the sidebar+detail split or `WelcomeView` is mounted.
struct ToolbarHomeButton: View {
  let isShowingWelcomeScreen: Bool
  let terminalManager: WorktreeTerminalManager
  let isFullScreen: Bool
  let action: () -> Void

  var body: some View {
    ToolbarGlassCapsuleButton(action: action) {
      Image(systemName: isShowingWelcomeScreen ? "house.fill" : "house")
        .foregroundStyle(isShowingWelcomeScreen ? .primary : .secondary)
        .frame(width: AppChromeMetrics.Toolbar.iconSize, height: AppChromeMetrics.Toolbar.iconSize)
        .accessibilityHidden(true)
    }
    .toolbarTintColorScheme(manager: terminalManager, isFullScreen: isFullScreen)
    .help("Home")
    .accessibilityLabel("Home")
  }
}
