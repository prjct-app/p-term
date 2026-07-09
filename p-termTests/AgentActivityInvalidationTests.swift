import IdentifiedCollections
import Testing

@testable import p_term

/// Locks the performance gate: agent activity churn (busy↔idle) must NOT
/// trigger a sidebar-structure recompute, while a real presence change
/// (agents appear / awaiting toggles) still must.
@MainActor
struct AgentActivityInvalidationTests {
  @Test func agentSnapshotChangedRecomputesStructure() {
    let action = SidebarItemFeature.Action.agentSnapshotChanged([], hasActivity: false)
    #expect(action.cacheInvalidations.contains(.sidebarStructure))
  }

  @Test func agentActivityChangedSkipsStructureRecompute() {
    let action = SidebarItemFeature.Action.agentActivityChanged([], hasActivity: true)
    #expect(action.cacheInvalidations.isEmpty)
  }

  @Test func terminalBusyChangedSkipsAllCacheRecomputes() {
    // Busy-only projection flips (command started/finished) are the
    // highest-frequency projection change during agent work; they must not
    // trigger the structure or notification-group recomputes.
    let action = SidebarItemFeature.Action.terminalBusyChanged(true)
    #expect(action.cacheInvalidations.isEmpty)
  }

  @Test func fullProjectionChangeStillRecomputesStructure() {
    let action = SidebarItemFeature.Action.terminalProjectionChanged(
      WorktreeRowProjection(
        surfaceIDs: [], isProgressBusy: false, hasUnseenNotifications: false, notifications: [])
    )
    #expect(action.cacheInvalidations.contains(.sidebarStructure))
    #expect(action.cacheInvalidations.contains(.toolbarNotificationGroups))
  }

  @Test func worktreeLineChangesLoadedSkipsStructureRecompute() {
    // Line-change polls hit every worktree on a 30s/60s cadence; structure never
    // reads added/removed lines, so they must not rebuild the sidebar plan.
    let action = RepositoriesFeature.Action.worktreeLineChangesLoaded(
      worktreeID: WorktreeID("perf/line-changes"),
      added: 1,
      removed: 2
    )
    #expect(action.cacheInvalidations.isEmpty)
  }

  @Test func worktreeNotificationReceivedSkipsDefaultStructureRecompute() {
    // Reorder-only path recomputes structure inside the reducer when order
    // actually changes; the default invalidation set stays empty.
    let action = RepositoriesFeature.Action.worktreeNotificationReceived(
      WorktreeID("perf/notification")
    )
    #expect(action.cacheInvalidations.isEmpty)
  }
}
