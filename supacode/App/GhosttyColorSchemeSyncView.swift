import AppKit
import Sharing
import SupacodeSettingsShared
import SwiftUI

/// Synchronizes the user's appearance mode preference with both NSApp appearance
/// and Ghostty's color scheme, and reloads Ghostty config when terminal theme sync is toggled.
struct GhosttyColorSchemeSyncView<Content: View>: View {
  @Environment(\.colorScheme) private var systemColorScheme
  @Shared(.settingsFile) private var settingsFile
  let ghostty: GhosttyRuntime
  let content: Content

  init(ghostty: GhosttyRuntime, @ViewBuilder content: () -> Content) {
    self.ghostty = ghostty
    self.content = content()
  }

  var body: some View {
    let resolved = settingsFile.global.appearanceMode.resolved(systemColorScheme: systemColorScheme)
    content
      .task {
        applyAppAppearance()
        ghostty.setColorScheme(resolved)
        AppFontRegistry.shared.refresh(from: settingsFile.global.uiFontSelection)
      }
      .onChange(of: settingsFile.global.appearanceMode) {
        applyAppAppearance()
      }
      .onChange(of: resolved) { _, newValue in
        ghostty.setColorScheme(newValue)
      }
      .onChange(of: settingsFile.global.terminalThemeSyncEnabled) {
        ghostty.reloadAppConfig()
      }
      .onChange(of: settingsFile.global.terminalFontSelection) {
        ghostty.reloadAppConfig()
      }
      .onChange(of: settingsFile.global.uiFontSelection) { _, newValue in
        AppFontRegistry.shared.refresh(from: newValue)
      }
  }

  private func applyAppAppearance() {
    let appearance: NSAppearance? =
      switch settingsFile.global.appearanceMode {
      case .system: nil
      case .light: NSAppearance(named: .aqua)
      case .dark: NSAppearance(named: .darkAqua)
      }
    NSApp.appearance = appearance
    for window in NSApp.windows {
      window.appearance = appearance
    }
  }
}
