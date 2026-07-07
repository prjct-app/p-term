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
  let insertAgentFleetPane: ((TerminalTabID) -> Void)?
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
        insertAgentFleetPane: insertAgentFleetPane,
      )
      // Bottom hairline for the trailing region (gap + accessories). The TABS
      // draw their own bottom separator per-tab via `TerminalTabBackground` —
      // inactive tabs get the line, the ACTIVE tab suppresses it so the selected
      // workspace merges into its terminals below. Together this is a continuous
      // bottom border across the whole bar EXCEPT under the active tab, which is
      // exactly the tabs↔terminals separation the design calls for.
      HStack(spacing: 0) {
        Spacer(minLength: 0)
        TerminalTabBarTrailingAccessories(
          createTab: createTab,
          split: split,
          canSplit: canSplit
        )
      }
      .frame(maxHeight: .infinity)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(chromeAppearance.overlayTint.opacity(chromeAppearance.separatorOpacity))
          .frame(height: pixelLength)
          .allowsHitTesting(false)
      }
    }
    .frame(height: TerminalTabBarMetrics.barHeight)
    .saturation(controlActiveState == .inactive ? 0 : 1)
    .clipped()
  }
}
