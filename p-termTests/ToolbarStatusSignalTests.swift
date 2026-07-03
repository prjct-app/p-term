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
    pullRequest: GithubPullRequest? = nil,
    branchName: String = "",
    pinnedMode: ToolbarStatusWidgetMode = .auto
  ) -> ToolbarStatusSignal.Inputs {
    ToolbarStatusSignal.Inputs(
      activeTabAgents: activeTabAgents,
      activeTabIsRunningScript: activeTabIsRunningScript,
      activeTabTitle: activeTabTitle,
      pullRequest: pullRequest,
      branchName: branchName,
      pinnedMode: pinnedMode,
      now: now
    )
  }

  @Test func agentAwaitingInputWinsOverEverything() {
    let agents: [AgentPresenceFeature.AgentInstance] = [
      .init(agent: .claude, activity: .awaitingInput)
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
      .init(agent: .codex, activity: .busy)
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
      .init(agent: .codex, activity: .idle)
    ]
    let resolved = ToolbarStatusSignal.resolve(
      Self.inputs(activeTabAgents: agents, branchName: "main")
    )
    #expect(resolved == .branch(name: "main"))
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

  @Test func closedPullRequestDoesNotDisplayFallsToBranch() {
    let pullRequest = Self.pullRequest(state: "CLOSED")
    let resolved = ToolbarStatusSignal.resolve(Self.inputs(pullRequest: pullRequest, branchName: "main"))
    #expect(resolved == .branch(name: "main"))
  }

  @Test func branchWinsOverTime() {
    let resolved = ToolbarStatusSignal.resolve(Self.inputs(branchName: "main"))
    #expect(resolved == .branch(name: "main"))
  }

  @Test func emptyBranchFallsToTime() {
    let resolved = ToolbarStatusSignal.resolve(Self.inputs(branchName: ""))
    #expect(resolved == .time(Self.now))
  }

  @Test func pinnedModeSelectsApplicableSignalOverHigherAutoPriority() {
    let agents: [AgentPresenceFeature.AgentInstance] = [
      .init(agent: .claude, activity: .awaitingInput)
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
    #expect(resolved == .branch(name: "main"))
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
