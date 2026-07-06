import ComposableArchitecture
import Foundation

/// The single, app-wide "which terminal is focused" identity. A terminal is a
/// pane (surface), so this is the first-class selection every feature — sidebar
/// selection, the toolbar status island, and future per-terminal features —
/// resolves through, instead of each re-deriving worktree → active tab →
/// active surface on its own (which is how they used to silently disagree).
///
/// It is intentionally a *derivation* over existing observed state rather than a
/// stored, separately-mutated field: the focused terminal is always exactly the
/// selected worktree's selected tab's active surface, so computing it keeps it
/// correct by construction with no denormalized value to keep in sync.
///
/// The workspace (tab) and worktree (folder) it belongs to travel alongside the
/// surface id because lookups and git/agent scoping need them — but identity is
/// the `surfaceID`, and git/branch is an attribute of the terminal, never the
/// key (see the domain-model decision in prjct).
struct FocusedTerminal: Equatable, Sendable {
  /// The folder/worktree the focused terminal's workspace opened from.
  let worktreeID: Worktree.ID
  /// The workspace (tab) that contains the focused terminal.
  let tabID: TerminalTabID
  /// The focused terminal itself — the surface (pane) UUID. This is the identity.
  let surfaceID: UUID

  /// Resolve the focused terminal from the two observed sources of truth: the
  /// globally-selected worktree and the per-tab feature states. Returns `nil`
  /// when nothing is selected yet, when the selected worktree has no selected
  /// tab, or when that tab hasn't resolved an active surface.
  ///
  /// Filtering the selected tab by `worktreeID` is load-bearing: each worktree's
  /// terminal state tracks its own `selectedTabId`, so several tabs across
  /// different worktrees can each be `isSelected` at once; only the one under
  /// the selected worktree is the app-wide focus.
  static func resolve(
    selectedWorktreeID: Worktree.ID?,
    terminalTabs: IdentifiedArrayOf<TerminalTabFeature.State>
  ) -> FocusedTerminal? {
    guard let worktreeID = selectedWorktreeID,
      let tab = terminalTabs.first(where: { $0.worktreeID == worktreeID && $0.isSelected }),
      let surfaceID = tab.activeSurfaceID
    else { return nil }
    return FocusedTerminal(worktreeID: worktreeID, tabID: tab.id, surfaceID: surfaceID)
  }

}
