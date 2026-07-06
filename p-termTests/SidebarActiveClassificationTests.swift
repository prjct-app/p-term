import Testing

@testable import p_term

@MainActor
struct SidebarActiveClassificationTests {
  @Test func unreadAwaitingRunningTakesTopPriority() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: true, hasAwaiting: true, hasAgent: true, hasRunning: true, hasOpenSession: false
    )
    #expect(classification == .unreadAwaitingRunning)
  }

  @Test func unreadAwaitingWithoutRunning() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: true, hasAwaiting: true, hasAgent: true, hasRunning: false, hasOpenSession: false
    )
    #expect(classification == .unreadAwaiting)
  }

  @Test func unreadAgentRunningTakesPrecedenceOverUnreadAgent() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: true, hasAwaiting: false, hasAgent: true, hasRunning: true, hasOpenSession: false
    )
    #expect(classification == .unreadAgentRunning)
  }

  @Test func unreadAgentWithoutRunning() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: true, hasAwaiting: false, hasAgent: true, hasRunning: false, hasOpenSession: false
    )
    #expect(classification == .unreadAgent)
  }

  @Test func unreadRunningWithNoAgent() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: true, hasAwaiting: false, hasAgent: false, hasRunning: true, hasOpenSession: false
    )
    #expect(classification == .unreadRunning)
  }

  @Test func awaitingRunningWithoutUnread() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: false, hasAwaiting: true, hasAgent: true, hasRunning: true, hasOpenSession: false
    )
    #expect(classification == .awaitingRunning)
  }

  @Test func awaitingOnly() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: false, hasAwaiting: true, hasAgent: true, hasRunning: false, hasOpenSession: false
    )
    #expect(classification == .awaiting)
  }

  @Test func agentRunningWithoutAwaiting() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: false, hasAwaiting: false, hasAgent: true, hasRunning: true, hasOpenSession: false
    )
    #expect(classification == .agentRunning)
  }

  @Test func agentOnly() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: false, hasAwaiting: false, hasAgent: true, hasRunning: false, hasOpenSession: false
    )
    #expect(classification == .agent)
  }

  @Test func runningOnly() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: false, hasAwaiting: false, hasAgent: false, hasRunning: true, hasOpenSession: false
    )
    #expect(classification == .running)
  }

  @Test func idleRowWithNoSessionDoesNotClassify() {
    let classification = SidebarActiveClassification.classify(
      hasUnread: false, hasAwaiting: false, hasAgent: false, hasRunning: false, hasOpenSession: false
    )
    #expect(classification == nil)
  }

  @Test func idleRowWithOpenSessionClassifiesAsOpenSession() {
    // A workspace with a live terminal but no activity still belongs in Active
    // (workspace-focused), at the lowest priority.
    let classification = SidebarActiveClassification.classify(
      hasUnread: false, hasAwaiting: false, hasAgent: false, hasRunning: false, hasOpenSession: true
    )
    #expect(classification == .openSession)
  }

  @Test func prioritiesOrderedAsSpec() {
    // The bucket priority ordering is the user contract; lock it explicitly
    // so a future shuffle of the enum case order can't silently re-rank.
    let expected: [SidebarActiveClassification] = [
      .unreadAwaitingRunning, .unreadAwaiting, .unreadAgentRunning, .unreadAgent,
      .unreadRunning, .awaitingRunning, .awaiting, .agentRunning, .agent, .running,
      .openSession,
    ]
    #expect(SidebarActiveClassification.allCases == expected)
  }
}
