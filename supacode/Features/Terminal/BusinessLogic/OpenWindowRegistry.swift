import Foundation

/// Tracks how many secondary `WorktreeWindowView` instances (see `WindowGroup(for:
/// WorktreeID.self)` in `supacodeApp.swift`) are currently open per worktree, so the sidebar can
/// render a worktree with 2+ open windows as a group instead of a single flat row.
///
/// Deliberately only tracks SECONDARY windows — the main window's implicit view of a worktree
/// (via `repositories.selectedWorktreeID`) never registers here, so a group never appears just
/// because the user is normally looking at a worktree in the main window.
///
/// A plain `@Observable` (not TCA state): it mirrors real `WindowGroup` scene instances, which
/// have no natural home in `RepositoriesFeature.State` without a new dependency-client bridge.
/// The sidebar reads this directly via `@Environment` — presentation-only for now, so it doesn't
/// affect row ordering, pinning, or hoisting. Bridge it into TCA (mirroring `TerminalClient`)
/// only if a later feature needs open-window count to affect sort order.
@MainActor
@Observable
final class OpenWindowRegistry {
  struct WindowInstanceID: Hashable, Sendable {
    let rawValue = UUID()
  }

  private(set) var instancesByWorktree: [WorktreeID: [WindowInstanceID]] = [:]

  func registerOpened(_ instance: WindowInstanceID, for worktreeID: WorktreeID) {
    instancesByWorktree[worktreeID, default: []].append(instance)
  }

  func registerClosed(_ instance: WindowInstanceID, for worktreeID: WorktreeID) {
    instancesByWorktree[worktreeID]?.removeAll { $0 == instance }
    if instancesByWorktree[worktreeID]?.isEmpty == true {
      instancesByWorktree.removeValue(forKey: worktreeID)
    }
  }

  func windowCount(for worktreeID: WorktreeID) -> Int {
    instancesByWorktree[worktreeID]?.count ?? 0
  }
}
