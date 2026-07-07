import AppKit
import SwiftUI

/// Shared pane chrome so tiled and paper layouts render every terminal/native
/// pane as the SAME bordered, spaced card — one visual language for "this is
/// a pane" regardless of which layout mode is showing it.
enum PaneChromeMetrics {
  /// Gap between adjacent panes: paper mode gets this as real layout spacing
  /// (`VStack`/column spacing); tiled mode gets it as half-padding on each
  /// leaf so two neighbors' padding sums to the same visual gap without
  /// touching `SplitView`'s own divider math.
  static let gap: CGFloat = 8
  // Reuses the app's own row-radius token (`AppDesign.Radius.row`, the same
  // one the sidebar's rows/cards render with) instead of a made-up value —
  // "consistent" means matching what the rest of the chrome already uses,
  // not picking a new number that merely LOOKS internally consistent.
  static let cornerRadius: CGFloat = AppDesign.Radius.row
  static let borderWidth: CGFloat = 1.5

  static func borderColor(isActive: Bool) -> Color {
    // Inactive stroke reuses the app's own subtle-border opacity token
    // (`AppDesign.Stroke.subtleOpacity`, the same one `AppRowSurface` draws
    // its own border with); active keeps the accent highlight since a pane
    // (unlike a plain row) needs to show which one has focus.
    isActive ? Color.accentColor.opacity(0.6) : Color.primary.opacity(AppDesign.Stroke.subtleOpacity)
  }
}

extension View {
  /// Clips to a rounded rect and strokes it — the border half of
  /// `PaneChromeMetrics`. Callers still own their own padding/gap since
  /// tiled and paper panes get that from different places.
  func paneCardChrome(isActive: Bool) -> some View {
    clipShape(.rect(cornerRadius: PaneChromeMetrics.cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: PaneChromeMetrics.cornerRadius, style: .continuous)
          .strokeBorder(PaneChromeMetrics.borderColor(isActive: isActive), lineWidth: PaneChromeMetrics.borderWidth)
      }
  }
}
