import SwiftUI

/// Shared "Dynamic-Island-style" capsule chrome for pill-shaped toolbar
/// controls (status island, notifications button, home button). Native
/// toolbar `Menu` items (the open-in-editor and script menus) get their pill
/// look for free from AppKit's own toolbar-item material, but that material
/// only tracks system light/dark — it has no way to reflect p/term's actual
/// terminal theme. So these controls draw their own capsule instead, filled
/// with the real terminal background color (`surfaceChromeAppearance`) using
/// the same fill+glassEffect pattern as `SidebarCardView`.
struct ToolbarGlassCapsuleButton<Label: View>: View {
  @Environment(\.surfaceChromeAppearance) private var chromeAppearance
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
        .padding(.horizontal, AppChromeMetrics.Toolbar.horizontalPadding)
        .padding(.vertical, AppChromeMetrics.Toolbar.verticalPadding)
        .frame(minHeight: AppChromeMetrics.Toolbar.controlHeight)
    }
    .buttonStyle(.plain)
    .background(
      chromeAppearance.backgroundColor.opacity(0.55),
      in: RoundedRectangle(cornerRadius: AppDesign.Radius.toolbar, style: .continuous)
    )
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppDesign.Radius.toolbar, style: .continuous))
  }
}
