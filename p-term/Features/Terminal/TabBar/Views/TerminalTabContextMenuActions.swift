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
}
