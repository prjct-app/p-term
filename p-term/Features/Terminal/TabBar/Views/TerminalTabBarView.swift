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
    // Hairline under the whole tab bar so the tabs read as a distinct strip
    // above the terminal surfaces. The workspace top line lives over the tabs
    // themselves (see `TerminalTabsRowView`), never spanning the trailing
    // accessories.
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(chromeAppearance.overlayTint.opacity(chromeAppearance.separatorOpacity))
        .frame(height: pixelLength)
        .allowsHitTesting(false)
    }
    .saturation(controlActiveState == .inactive ? 0 : 1)
    .clipped()
  }
}
