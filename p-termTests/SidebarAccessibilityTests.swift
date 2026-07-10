import SwiftUI
import Testing

@testable import p_term

@Suite("SidebarAccessibility")
struct SidebarAccessibilityTests {
  @Test func workspaceRowLabelIncludesTitleAndRole() {
    #expect(SidebarAccessibility.workspaceRowLabel(title: "prjct-code") == "prjct-code workspace")
    #expect(SidebarAccessibility.workspaceRowLabel(title: "main") == "main workspace")
  }

  @Test func collapseControlLabelReflectsExpandedState() {
    #expect(SidebarAccessibility.collapseControlLabel(isCollapsed: true) == "Expand workspace")
    #expect(SidebarAccessibility.collapseControlLabel(isCollapsed: false) == "Collapse workspace")
  }

  @Test func workspaceRowTraitsAlwaysIncludeButton() {
    let unselected = SidebarAccessibility.workspaceRowTraits(isSelected: false)
    let selected = SidebarAccessibility.workspaceRowTraits(isSelected: true)
    #expect(unselected.contains(.isButton))
    #expect(!unselected.contains(.isSelected))
    #expect(selected.contains(.isButton))
    #expect(selected.contains(.isSelected))
  }
}
