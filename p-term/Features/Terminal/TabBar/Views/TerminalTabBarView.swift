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
  @Environment(\.pixelLength)
  private var pixelLength

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
    // No full-width bottom hairline here: it painted over the SELECTED tab too,
    // giving it a line the user shouldn't see. Each INACTIVE tab draws its own
    // bottom separator (`TerminalTabBackground`) and the active tab suppresses
    // its own, so the selected tab reads as merging into the surface below while
    // the strip stays distinct where there are inactive tabs.
    .saturation(controlActiveState == .inactive ? 0 : 1)
    .clipped()
  }
}
