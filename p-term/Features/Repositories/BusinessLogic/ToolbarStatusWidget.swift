import Foundation
import PTermSettingsShared

/// The single highest-priority "what's happening" signal for the toolbar
/// status island, scoped to the focused worktree's ACTIVE terminal tab only
/// (never an aggregate across tabs — see AGENTS.md "Toolbar status island").
/// Pure and state-shape-agnostic, mirroring `SidebarActiveClassification`'s
/// classifier shape and `SidebarBottomCardView.Slot`'s resolve+transitionToken
/// pattern for animatable state.
enum ToolbarStatusSignal: Equatable {
  case agentAwaitingInput(SkillAgent)
  case agentWorking(SkillAgent)
  case runningScript(tabTitle: String)
  case pullRequest(PullRequestStatusModel)
  case branch(name: String)
  case time(Date)

  struct Inputs: Equatable {
    /// Agents attached to the active tab only (`TerminalTabFeature.State.agents`).
    let activeTabAgents: [AgentPresenceFeature.AgentInstance]
    /// `TerminalTabItem.isBlockingScript && !isBlockingScriptCompleted` for the active tab.
    let activeTabIsRunningScript: Bool
    let activeTabTitle: String
    let pullRequest: GithubPullRequest?
    let branchName: String
    let pinnedMode: ToolbarStatusWidgetMode
    let now: Date

    init(
      activeTabAgents: [AgentPresenceFeature.AgentInstance],
      activeTabIsRunningScript: Bool,
      activeTabTitle: String,
      pullRequest: GithubPullRequest?,
      branchName: String,
      pinnedMode: ToolbarStatusWidgetMode,
      now: Date
    ) {
      self.activeTabAgents = activeTabAgents
      self.activeTabIsRunningScript = activeTabIsRunningScript
      self.activeTabTitle = activeTabTitle
      self.pullRequest = pullRequest
      self.branchName = branchName
      self.pinnedMode = pinnedMode
      self.now = now
    }
  }

  /// Priority (highest first): agent awaiting input > agent working > running
  /// script > pull request > branch > time. `pinnedMode` selects among
  /// signals that already apply — pinning a signal that isn't currently
  /// applicable falls through to full auto-priority rather than rendering
  /// nothing.
  static func resolve(_ inputs: Inputs) -> Self {
    let auto = autoResolve(inputs)
    guard inputs.pinnedMode != .auto else { return auto }
    if let pinned = pinnedResolve(inputs) {
      return pinned
    }
    return auto
  }

  private static func autoResolve(_ inputs: Inputs) -> Self {
    if let agent = inputs.activeTabAgents.first(where: \.awaitingInput) {
      return .agentAwaitingInput(agent.agent)
    }
    if let agent = inputs.activeTabAgents.first(where: { $0.activity == .busy }) {
      return .agentWorking(agent.agent)
    }
    if inputs.activeTabIsRunningScript {
      return .runningScript(tabTitle: inputs.activeTabTitle)
    }
    if let model = PullRequestStatusModel(pullRequest: inputs.pullRequest) {
      return .pullRequest(model)
    }
    if !inputs.branchName.isEmpty {
      return .branch(name: inputs.branchName)
    }
    return .time(inputs.now)
  }

  /// Returns the pinned signal only if it currently applies; `nil` otherwise
  /// (caller falls back to `autoResolve`).
  private static func pinnedResolve(_ inputs: Inputs) -> Self? {
    switch inputs.pinnedMode {
    case .auto:
      return nil
    case .agent:
      if let agent = inputs.activeTabAgents.first(where: \.awaitingInput) {
        return .agentAwaitingInput(agent.agent)
      }
      if let agent = inputs.activeTabAgents.first(where: { $0.activity == .busy }) {
        return .agentWorking(agent.agent)
      }
      return nil
    case .script:
      return inputs.activeTabIsRunningScript ? .runningScript(tabTitle: inputs.activeTabTitle) : nil
    case .pullRequest:
      return PullRequestStatusModel(pullRequest: inputs.pullRequest).map { .pullRequest($0) }
    case .branch:
      return inputs.branchName.isEmpty ? nil : .branch(name: inputs.branchName)
    case .time:
      return .time(inputs.now)
    }
  }

  /// Hashable identity used by `.animation(_:value:)`, mirroring
  /// `SidebarBottomCardView.Slot.transitionToken`. `.time` uses a constant
  /// token (not keyed on `Date`) so the capsule doesn't re-morph every minute
  /// — only its text/icon cross-fade via `TimelineView`.
  var transitionToken: String {
    switch self {
    case .agentAwaitingInput(let agent): "agentAwaitingInput:\(agent)"
    case .agentWorking(let agent): "agentWorking:\(agent)"
    case .runningScript(let tabTitle): "runningScript:\(tabTitle)"
    case .pullRequest(let model): "pullRequest:\(model.number):\(model.state ?? "")"
    case .branch(let name): "branch:\(name)"
    case .time: "time"
    }
  }
}
