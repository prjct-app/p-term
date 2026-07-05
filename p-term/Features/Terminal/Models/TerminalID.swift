import Foundation

/// Stable identity of a single terminal — a pane (surface). Wraps the surface
/// `UUID` in a branded type so a terminal id can't be passed where a raw UUID
/// (or a `TerminalTabID`) is expected, mirroring `TerminalTabID`.
///
/// A terminal is the first-class unit of the app's model: a workspace (tab)
/// groups terminals, a project groups workspaces, and git/branch is an
/// attribute of a terminal, never its identity (see the domain-model decision
/// in prjct). The raw value is the same surface UUID persisted in
/// `layouts.json`, so a `TerminalID` is stable across relaunches.
nonisolated struct TerminalID: Hashable, Identifiable, Codable, Sendable {
  let rawValue: UUID

  init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  var id: UUID { rawValue }
}
