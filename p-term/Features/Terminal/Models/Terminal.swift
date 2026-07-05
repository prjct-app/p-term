import ComposableArchitecture
import Foundation
import PTermSettingsShared

/// The highest-priority activity state of a single terminal (pane). Derived from
/// its agent presence, progress stripe, and last exit code. Lives here (not in a
/// view) so the sidebar, the toolbar island, and future per-terminal features
/// classify status the same way.
enum TerminalStatus: Equatable, Sendable {
  case needsAttention
  case running
  case completed
  case failed
  case idle

  init(
    agents: [AgentPresenceFeature.AgentInstance],
    progressDisplay: TerminalTabProgressDisplay?,
    exitCode: Int?
  ) {
    if agents.contains(where: { $0.activity == .awaitingInput }) {
      self = .needsAttention
      return
    }
    if progressDisplay?.style == .error {
      self = .failed
      return
    }
    if agents.contains(where: { $0.activity == .busy }) || progressDisplay != nil {
      self = .running
      return
    }
    if let exitCode {
      self = exitCode == 0 ? .completed : .failed
      return
    }
    if !agents.isEmpty {
      self = .completed
      return
    }
    self = .idle
  }

  var isAnimated: Bool {
    switch self {
    case .needsAttention, .running: true
    case .completed, .failed, .idle: false
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .needsAttention: "Needs attention"
    case .running: "Running"
    case .completed: "Completed"
    case .failed: "Failed"
    case .idle: "Idle"
    }
  }
}

/// A first-class terminal (pane): its stable identity plus the per-terminal state
/// that used to be scattered across `WorktreeTerminalState` dicts, the tab
/// projection, and view-local derivation. Assembled from a tab's per-surface
/// state via `resolve` so every consumer reads one shape instead of poking the
/// tab's dictionaries by surface id. New per-terminal features add a field here
/// and populate it in `resolve`, not in four separate layers.
struct Terminal: Equatable, Identifiable, Sendable {
  let id: TerminalID
  let worktreeID: Worktree.ID
  /// The workspace (tab) that groups this terminal.
  let tabID: TerminalTabID
  /// 1-based position within a split, or `nil` for a single-terminal workspace.
  let paneIndex: Int?
  /// Number of terminals in the workspace; `1` means no split.
  let paneCount: Int
  /// User-set name; overrides the derived title.
  let customTitle: String?
  /// User-set tint for quick identification.
  let tintColor: RepositoryColor?
  /// Agents attached to this terminal (already scoped to this pane).
  let agents: [AgentPresenceFeature.AgentInstance]
  let status: TerminalStatus
  /// Git branch resolved from this terminal's own working directory. `nil` when
  /// the cwd isn't a repo or is on a detached HEAD. An attribute of the
  /// terminal, not the workspace — panes that `cd` elsewhere diverge.
  let gitBranch: String?
  /// Raw process/terminal title reported by the shell, if any.
  let rawProcessTitle: String?
  /// Names of the owning project/branch/folder, used to suppress a process
  /// title that merely echoes the workspace name.
  let aliasCandidates: [String]

  /// Assemble a terminal from its workspace (tab) state and its surface id.
  static func resolve(
    id: TerminalID,
    tab: TerminalTabFeature.State,
    paneIndex: Int?,
    paneCount: Int,
    aliasCandidates: [String?]
  ) -> Terminal {
    let surfaceID = id.rawValue
    let agents = tab.agents.filter { $0.surfaceID == surfaceID }
    let status = TerminalStatus(
      agents: agents,
      progressDisplay: tab.surfaceProgressDisplays[surfaceID],
      exitCode: tab.surfaceExitCodes[surfaceID]
    )
    return Terminal(
      id: id,
      worktreeID: tab.worktreeID,
      tabID: tab.id,
      paneIndex: paneIndex,
      paneCount: paneCount,
      customTitle: tab.surfaceCustomTitles[surfaceID],
      tintColor: tab.surfaceTintColors[surfaceID],
      agents: agents,
      status: status,
      gitBranch: tab.surfaceGitBranches[surfaceID],
      rawProcessTitle: tab.surfaceTitles[surfaceID],
      aliasCandidates: aliasCandidates.compactMap { candidate in
        candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
      }.filter { !$0.isEmpty }
    )
  }

  /// The name to show: user rename → detected agent(s) → a useful process
  /// title → "Shell". Priority matches the previous view-local logic exactly.
  var displayTitle: String {
    if let customTitle { return customTitle }
    if !agents.isEmpty {
      return agents.map(\.agent.displayName).joined(separator: " + ")
    }
    if let processTitle = usefulProcessTitle {
      return processTitle
    }
    return "Shell"
  }

  /// A process title worth showing, or `nil` when it's empty, a bare shell, an
  /// echo of the workspace name, or a path/host string. Recognizes known agent
  /// CLIs by name so an un-hooked agent still reads as itself.
  var usefulProcessTitle: String? {
    guard let raw = rawProcessTitle else { return nil }
    let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title != "Terminal" else { return nil }
    let lower = title.lowercased()
    if lower.contains("claude") { return "Claude Code" }
    if lower.contains("codex") { return "Codex" }
    if lower.contains("cursor") { return "Cursor" }
    if lower.contains("copilot") { return "Copilot CLI" }
    if lower.contains("kimi") { return "Kimi CLI" }
    if lower.contains("opencode") { return "OpenCode" }
    if aliasCandidates.contains(where: { $0.lowercased() == lower }) { return nil }
    if title.contains("@") || title.contains("~") || title.contains("/") || title.contains(":") {
      return nil
    }
    return title
  }
}

extension TerminalsFeature.State {
  /// Assemble the first-class `Terminal` for a surface id, scanning the tabs for
  /// its owning workspace. The single addressable entry point for any feature
  /// that needs a terminal's per-pane state by id. `aliasCandidates` (project /
  /// branch / folder names) let the title logic suppress a process title that
  /// merely echoes the workspace.
  func terminal(id: TerminalID, aliasCandidates: [String?] = []) -> Terminal? {
    let surfaceID = id.rawValue
    for tab in terminalTabs where tab.surfaceIDs.contains(surfaceID) {
      let paneCount = tab.surfaceIDs.count
      let paneIndex = paneCount > 1 ? tab.surfaceIDs.firstIndex(of: surfaceID).map { $0 + 1 } : nil
      return Terminal.resolve(
        id: id,
        tab: tab,
        paneIndex: paneIndex,
        paneCount: paneCount,
        aliasCandidates: aliasCandidates
      )
    }
    return nil
  }
}
