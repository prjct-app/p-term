import SwiftUI

/// Shared accessibility copy for interactive sidebar rows.
/// Kept pure so unit tests can lock the VoiceOver strings without hosting views.
enum SidebarAccessibility {
  static func workspaceRowLabel(title: String) -> String {
    "\(title) workspace"
  }

  static func collapseControlLabel(isCollapsed: Bool) -> String {
    isCollapsed ? "Expand workspace" : "Collapse workspace"
  }

  static func newTerminalCTALabel() -> String {
    "New Terminal"
  }

  static func workspaceRowTraits(isSelected: Bool) -> AccessibilityTraits {
    var traits: AccessibilityTraits = .isButton
    if isSelected {
      traits.insert(.isSelected)
    }
    return traits
  }
}
