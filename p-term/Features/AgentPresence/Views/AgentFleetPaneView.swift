import ComposableArchitecture
import SwiftUI

/// Native (non-terminal) split-tree pane version of the Agent Fleet — same
/// content as the toolbar popover (`AgentFleetPopoverView`), full-bleed
/// instead of a fixed popover frame. Reads `store.state.computeAgentFleetGroups()`
/// directly in its own tracked `body` (same pattern as
/// `WorktreeDetailView.AgentFleetPopoverButtonHost`) so it stays live for as
/// long as the pane is mounted — this view's `NSHostingView` wrapper is
/// created once at split time and never rebuilt, so the liveness has to come
/// from Observation inside this view, not from the caller re-constructing it.
struct AgentFleetPaneView: View {
  let store: StoreOf<AppFeature>
  let onSelect: (Worktree.ID, UUID) -> Void

  var body: some View {
    let groups = store.state.computeAgentFleetGroups()
    if groups.isEmpty {
      ContentUnavailableView(
        "No agents running",
        systemImage: "person.2",
        description: Text("Agents running in any project's terminals will show up here.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      AgentFleetPopoverView(groups: groups, onSelect: onSelect)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }
}
