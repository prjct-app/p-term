import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

struct TerminalTabBarView: View {
  @Bindable var manager: TerminalTabManager
  let terminalState: WorktreeTerminalState
  let terminalsStore: StoreOf<TerminalsFeature>
  let createTab: () -> Void
  let split: (TerminalSplitMenuDirection) -> Void
  let canSplit: Bool
  let closeTab: (TerminalTabID) -> Void
  let closeOthers: (TerminalTabID) -> Void
  let closeToRight: (TerminalTabID) -> Void
  let closeAll: () -> Void
  let dismissSplitZoom: (TerminalTabID) -> Void
  let renameTab: (TerminalTabID, String) -> Void
  @Environment(\.controlActiveState)
  private var controlActiveState
  @Environment(\.surfaceChromeAppearance)
  private var chromeAppearance

  var body: some View {
    HStack(spacing: 0) {
      TerminalTabsView(
        manager: manager,
        terminalState: terminalState,
        terminalsStore: terminalsStore,
        closeTab: closeTab,
        closeOthers: closeOthers,
        closeToRight: closeToRight,
        closeAll: closeAll,
        dismissSplitZoom: dismissSplitZoom,
        renameTab: renameTab,
      )
      Spacer(minLength: 0)
      TerminalTabBarTrailingAccessories(
        createTab: createTab,
        split: split,
        canSplit: canSplit
      )
    }
    .frame(height: TerminalTabBarMetrics.barHeight)
    // Bar-wide workspace line: extends the active tab's top stripe across the
    // sibling tabs and trailing accessories so the workspace color reads
    // continuous. Drawn as a `background` (BEHIND the tabs), so the active tab's
    // own `TerminalTabProgressStripe` paints ON TOP — a running/errored active
    // tab still shows its blue/red progress stripe while the workspace color
    // fills the rest of the bar.
    .background(alignment: .top) {
      Rectangle()
        .fill(workspaceLineColor)
        .opacity(workspaceLineOpacity)
        .frame(height: TerminalTabBarMetrics.activeIndicatorHeight)
        .allowsHitTesting(false)
    }
    .saturation(controlActiveState == .inactive ? 0 : 1)
    .clipped()
  }

  private var selectedTab: TerminalTabItem? {
    guard let selectedTabId = manager.selectedTabId else { return nil }
    return manager.tabs.first(where: { $0.id == selectedTabId })
  }

  private var workspaceLineColor: Color {
    selectedTab?.tintColor?.color ?? chromeAppearance.overlayTint
  }

  private var workspaceLineOpacity: Double {
    selectedTab?.tintColor != nil ? 1 : chromeAppearance.secondaryAccentOpacity
  }
}
