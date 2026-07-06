import Foundation
import Testing

@testable import PTermSettingsShared
@testable import p_term

@MainActor
struct ToolbarStatusSignalTests {
  private static let now = Date(timeIntervalSince1970: 0)

  private static func pullRequest(state: String = "OPEN", number: Int = 1) -> GithubPullRequest {
    GithubPullRequest(
      number: number,
      title: "PR",
      state: state,
      additions: 0,
      deletions: 0,
      isDraft: false,
      reviewDecision: nil,
      mergeable: nil,
      mergeStateStatus: nil,
      updatedAt: nil,
      url: "https://example.com/pull/\(number)",
      headRefName: "feature",
      baseRefName: "main",
      commitsCount: 1,
      authorLogin: "khoi",
      statusCheckRollup: nil,
      mergeQueueEntry: nil
    )
  }

  private static func inputs(
    activeTabAgents: [AgentPresenceFeature.AgentInstance] = [],
    activeTabIsRunningScript: Bool = false,
    activeTabTitle: String = "tab",
    activeTabTitleAgent: String? = nil,
    pullRequest: GithubPullRequest? = nil,
    branchName: String = "",
    pinnedMode: ToolbarStatusWidgetMode = .auto
  ) -> ToolbarStatusSignal.Inputs {
    ToolbarStatusSignal.Inputs(
      activeTabAgents: activeTabAgents,
      activeTabIsRunningScript: activeTabIsRunningScript,
      activeTabTitle: activeTabTitle,
      activeTabTitleAgent: activeTabTitleAgent,
      pullRequest: pullRequest,
      branchName: branchName,
      pinnedMode: pinnedMode,
      now: now
    )
  }

  @Test func agentAwaitingInputWinsOverEverything() {
    let agents: [AgentPresenceFeature.AgentInstance] = [
      .init(agent: .claude, surfaceID: UUID(), activity: .awaitingInput)
    ]
    let resolved = ToolbarStatusSignal.resolve(
      Self.inputs(
        activeTabAgents: agents,
        activeTabIsRunningScript: true,
        pullRequest: Self.pullRequest(),
        branchName: "main"
      )
    )
    #expect(resolved == .agentAwaitingInput(.claude))
  }

  @Test func agentWorkingWinsOverScriptsPRAndBranch() {
    let agents: [AgentPresenceFeature.AgentInstance] = [
      .init(agent: .codex, surfaceID: UUID(), activity: .busy)
    ]
    let resolved = ToolbarStatusSignal.resolve(
      Self.inputs(
        activeTabAgents: agents,
        activeTabIsRunningScript: true,
        pullRequest: Self.pullRequest(),
        branchName: "main"
      )
    )
    #expect(resolved == .agentWorking(.codex))
  }

  @Test func idleAgentDoesNotCountAsWorking() {
    let agents: [AgentPresenceFeature.AgentInstance] = [
      .init(agent: .codex, surfaceID: UUID(), activity: .idle)
    ]
    let resolved = ToolbarStatusSignal.resolve(
      Self.inputs(activeTabAgents: agents, branchName: "main")
    )
    // Auto mode: an idle agent is not "working", and with no PR the fallback is
    // the clock (`.time`), not the branch (branch only surfaces when pinned).
    #expect(resolved == .time(Self.now))
  }

  @Test func titleAgentSurfacesWhenNoHookedAgentIsPresent() {
    let resolved = ToolbarStatusSignal.resolve(
      Self.inputs(activeTabTitleAgent: "Cursor", branchName: "main")
    )
    #expect(resolved == .titleAgent(name: "Cursor"))
  }

  @Test func hookedAgentSuppressesTitleAgent() {
    let agents: [AgentPresenceFeature.AgentInstance] = [
      .init(agent: .codex, surfaceID: UUID(), activity: .busy)
    ]
    let resolved = ToolbarStatusSignal.resolve(
      Self.inputs(activeTabAgents: agents, activeTabTitleAgent: "Cursor")
    )
    #expect(resolved == .agentWorking(.codex))
  }

  @Test func runningScriptWinsOverPRAndBranch() {
    let resolved = ToolbarStatusSignal.resolve(
      Self.inputs(
        activeTabIsRunningScript: true, activeTabTitle: "build.sh", pullRequest: Self.pullRequest(), branchName: "main")
    )
    #expect(resolved == .runningScript(tabTitle: "build.sh"))
  }

  @Test func pullRequestWinsOverBranch() {
    let pullRequest = Self.pullRequest()
    let resolved = ToolbarStatusSignal.resolve(Self.inputs(pullRequest: pullRequest, branchName: "main"))
    #expect(resolved == .pullRequest(PullRequestStatusModel(pullRequest: pullRequest)!))
  }

  @Test func closedPullRequestDoesNotDisplayFallsToTime() {
    let pullRequest = Self.pullRequest(state: "CLOSED")
    let resolved = ToolbarStatusSignal.resolve(Self.inputs(pullRequest: pullRequest, branchName: "main"))
    #expect(resolved == .time(Self.now))
  }

  @Test func autoFallsToTimeEvenWithBranch() {
    let resolved = ToolbarStatusSignal.resolve(Self.inputs(branchName: "main"))
    #expect(resolved == .time(Self.now))
  }

  @Test func emptyBranchFallsToTime() {
    let resolved = ToolbarStatusSignal.resolve(Self.inputs(branchName: ""))
    #expect(resolved == .time(Self.now))
  }

  @Test func pinnedModeSelectsApplicableSignalOverHigherAutoPriority() {
    let agents: [AgentPresenceFeature.AgentInstance] = [
      .init(agent: .claude, surfaceID: UUID(), activity: .awaitingInput)
    ]
    let resolved = ToolbarStatusSignal.resolve(
      Self.inputs(activeTabAgents: agents, branchName: "main", pinnedMode: .branch)
    )
    #expect(resolved == .branch(name: "main"))
  }

  @Test func pinnedModeFallsBackToAutoWhenSignalNotApplicable() {
    let resolved = ToolbarStatusSignal.resolve(
      Self.inputs(branchName: "main", pinnedMode: .pullRequest)
    )
    #expect(resolved == .time(Self.now))
  }

  @Test func pinnedTimeIsAlwaysHonored() {
    let resolved = ToolbarStatusSignal.resolve(
      Self.inputs(pullRequest: Self.pullRequest(), branchName: "main", pinnedMode: .time)
    )
    #expect(resolved == .time(Self.now))
  }

  @Test func transitionTokenIsStableForSameSignalShape() {
    let lhs = ToolbarStatusSignal.branch(name: "main").transitionToken
    let rhs = ToolbarStatusSignal.branch(name: "main").transitionToken
    #expect(lhs == rhs)
  }

  @Test func transitionTokenDiffersForDifferentBranch() {
    let lhs = ToolbarStatusSignal.branch(name: "main").transitionToken
    let rhs = ToolbarStatusSignal.branch(name: "feature").transitionToken
    #expect(lhs != rhs)
  }

  @Test func transitionTokenForTimeIsConstant() {
    let lhs = ToolbarStatusSignal.time(Date(timeIntervalSince1970: 0)).transitionToken
    let rhs = ToolbarStatusSignal.time(Date(timeIntervalSince1970: 1_000)).transitionToken
    #expect(lhs == rhs)
  }
}
