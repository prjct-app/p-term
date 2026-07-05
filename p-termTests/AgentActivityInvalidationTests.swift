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
}
