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

  /// The agent detected from the process title (`KnownAgentCLI`) for an
  /// un-hooked agent that only announces itself via its title. `agent` is the
  /// `SkillAgent` (so the sidebar/island can render its real logo) when the
  /// detected CLI has one; `nil` `agent` means "an agent, but no logo asset"
  /// (e.g. Cursor/Gemini) — callers fall back to a generic glyph.
  var detectedTitleAgent: (name: String, agent: SkillAgent?)? {
    guard let raw = rawProcessTitle else { return nil }
    return KnownAgentCLI.match(inTitle: raw.lowercased())
  }

  /// Display name of the title-detected agent, if any.
  var detectedAgentName: String? { detectedTitleAgent?.name }

  /// A process title worth showing, or `nil` when it's empty, a bare shell, an
  /// echo of the workspace name, or a path/host string. Recognizes known agent
  /// CLIs by name so an un-hooked agent (one that doesn't emit presence hooks)
  /// still reads as itself.
  var usefulProcessTitle: String? {
    guard let raw = rawProcessTitle else { return nil }
    let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title != "Terminal" else { return nil }
    let lower = title.lowercased()
    if let agent = KnownAgentCLI.match(inTitle: lower) { return agent.name }
    if aliasCandidates.contains(where: { $0.lowercased() == lower }) { return nil }
    if title.contains("@") || title.contains("~") || title.contains("/") || title.contains(":") {
      return nil
    }
    return title
  }
}

/// Lightweight, hook-free agent detection from the terminal title. Most agent
/// CLIs set the tab title to their own name, so matching a distinctive token in
/// the (lowercased) title labels the terminal without polling the process table
/// or requiring presence hooks. Ordered most-specific first so e.g. `opencode`
/// wins before any shorter token. Only distinctive tokens are listed — short or
/// common words (amp, pi, cn, code) are omitted to avoid false positives.
/// Catalog verified 2026-07-05 against the market research of agentic CLIs.
enum KnownAgentCLI {
  /// Catalog entry: title token, display name, optional `SkillAgent` logo.
  /// `agent: nil` = recognized CLI with no bundled logo asset (generic glyph).
  struct Entry: Sendable, Equatable {
    let token: String
    let name: String
    let agent: SkillAgent?
  }

  /// Ordered most-specific first so e.g. `opencode` wins before any shorter token.
  /// `codex` maps to the OpenAI Codex mark; `claude` to the Claude mark, etc.
  static let catalog: [Entry] = [
    Entry(token: "opencode", name: "OpenCode", agent: .opencode),
    Entry(token: "claude", name: "Claude Code", agent: .claude),
    Entry(token: "codebuddy", name: "CodeBuddy", agent: nil),
    Entry(token: "codex", name: "Codex", agent: .codex),
    Entry(token: "cursor", name: "Cursor", agent: nil),
    Entry(token: "gemini", name: "Gemini CLI", agent: nil),
    Entry(token: "copilot", name: "Copilot CLI", agent: .copilot),
    Entry(token: "aider", name: "Aider", agent: nil),
    Entry(token: "goose", name: "Goose", agent: nil),
    Entry(token: "crush", name: "Crush", agent: nil),
    Entry(token: "droid", name: "Droid", agent: nil),
    Entry(token: "cline", name: "Cline", agent: nil),
    Entry(token: "kilocode", name: "Kilo Code", agent: nil),
    Entry(token: "qwen", name: "Qwen Code", agent: nil),
    Entry(token: "kimi", name: "Kimi CLI", agent: .kimi),
    Entry(token: "auggie", name: "Auggie", agent: nil),
    Entry(token: "openhands", name: "OpenHands", agent: nil),
    Entry(token: "rovodev", name: "Rovo Dev", agent: nil),
    Entry(token: "kiro", name: "Kiro", agent: .kiro),
    Entry(token: "grok", name: "Grok", agent: nil),
    Entry(token: "devin", name: "Devin", agent: nil),
    Entry(token: "jules", name: "Jules", agent: nil),
    Entry(token: "qodo", name: "Qodo", agent: nil),
    Entry(token: "plandex", name: "Plandex", agent: nil),
    Entry(token: "gptme", name: "gptme", agent: nil),
    Entry(token: "iflow", name: "iFlow", agent: nil),
  ]

  static func match(inTitle lowercasedTitle: String) -> (name: String, agent: SkillAgent?)? {
    for entry in catalog where lowercasedTitle.containsToken(entry.token) {
      return (entry.name, entry.agent)
    }
    return nil
  }
}

extension String {
  /// True when `token` appears as a whole word — bounded on both sides by a
  /// non-alphanumeric character or the string edge. Keeps `cursor-agent` /
  /// `running claude` matching while rejecting `precursor` / `codexample`.
  fileprivate func containsToken(_ token: String) -> Bool {
    guard !token.isEmpty else { return false }
    var searchStart = startIndex
    while let range = range(of: token, range: searchStart..<endIndex) {
      let beforeOK =
        range.lowerBound == startIndex
        || !self[index(before: range.lowerBound)].isLetterOrDigit
      let afterOK =
        range.upperBound == endIndex || !self[range.upperBound].isLetterOrDigit
      if beforeOK && afterOK { return true }
      searchStart = index(after: range.lowerBound)
    }
    return false
  }
}

extension Character {
  fileprivate var isLetterOrDigit: Bool { isLetter || isNumber }
}

extension TerminalTabFeature.State {
  /// Hook-free agent name detected from a surface's live title. The single
  /// home for the title→agent derivation — `Terminal.detectedAgentName` and
  /// the toolbar island both resolve through `KnownAgentCLI` via this shape.
  func detectedTitleAgent(for surfaceID: UUID) -> String? {
    surfaceTitles[surfaceID].flatMap { KnownAgentCLI.match(inTitle: $0.lowercased())?.name }
  }
}
