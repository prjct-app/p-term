import SwiftUI

/// Shared chrome for pill-shaped toolbar controls (status island,
/// notifications button, home button). Renders as a plain `Button` with no
/// custom capsule/glass drawing, so macOS applies the same automatic
/// shared-glass toolbar-item background that `Menu`-based controls like the
/// open-in-editor and script menus get — keeping every toolbar control in one
/// consistent visual family instead of two competing pill styles.
struct ToolbarGlassCapsuleButton<Label: View>: View {
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  var body: some View {
    Button(action: action, label: label)
  }
}
