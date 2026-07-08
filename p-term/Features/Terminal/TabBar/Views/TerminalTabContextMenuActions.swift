import PTermSettingsShared

struct TerminalTabContextMenuActions {
  let closeTab: (TerminalTabID) -> Void
  let closeOthers: (TerminalTabID) -> Void
  let closeToRight: (TerminalTabID) -> Void
  let closeAll: () -> Void
  let renameTab: (TerminalTabID) -> Void
  let setTintColor: (TerminalTabID, RepositoryColor?) -> Void
  /// Toggles between tiling and the Niri-style paper layout. Returns whether
  /// the toggle actually applied (a no-op if the tab has no tree/panes yet).
  let toggleLayoutMode: (TerminalTabID) -> Void
  /// Shows/hides the Git Diff panel attached to the focused pane in the tab.
  let toggleGitDiffPanel: (TerminalTabID) -> Void
  /// Splits a native Agent Fleet pane into the tab. `nil` where the
  /// app-level store this needs isn't threaded down (secondary per-worktree
  /// windows) — the menu item hides itself in that case.
  let insertAgentFleetPane: ((TerminalTabID) -> Void)?
}
