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

  /// Per-worktree observable box. Every sidebar row calls `windowCount(for:)` for its own fixed
  /// worktree ID, and Swift's Observation macro tracks access at whole-stored-property
  /// granularity — a single shared `[WorktreeID: Int]` dictionary would make every row an
  /// observer of every OTHER row's window-count changes too (opening one window would
  /// invalidate the entire sidebar, not just the one row it actually affects). A separate
  /// `@Observable` box per worktree keeps a mutation's invalidation scoped to just the rows
  /// that read THAT box, matching this codebase's existing per-leaf sidebar-invalidation
  /// contract (see CLAUDE.md "Sidebar performance").
  @MainActor
  @Observable
  final class Box {
    fileprivate(set) var instances: [WindowInstanceID] = []
    var count: Int { instances.count }
  }

  /// `@ObservationIgnored` deliberately: this dictionary is just a lazy-created lookup table for
  /// the per-worktree `Box`es above. Its own structural changes (a new worktree getting its
  /// first box) shouldn't invalidate anything — only a `Box`'s own `count` mutating should, and
  /// that's tracked independently since `Box` is its own `@Observable` type.
  @ObservationIgnored
  private var boxes: [WorktreeID: Box] = [:]

  func registerOpened(_ instance: WindowInstanceID, for worktreeID: WorktreeID) {
    box(for: worktreeID).instances.append(instance)
  }

  func registerClosed(_ instance: WindowInstanceID, for worktreeID: WorktreeID) {
    box(for: worktreeID).instances.removeAll { $0 == instance }
  }

  /// Always resolves through `box(for:)` (create-if-absent) rather than an optional dictionary
  /// read, so every call — including the first, before any window has opened for this worktree
  /// — touches a real `Box`'s tracked `count` property. Reading `nil?.count ?? 0` instead would
  /// establish no observation at all when no box exists yet, so a row that reads "0" before any
  /// window opens would never learn about a box created later.
  func windowCount(for worktreeID: WorktreeID) -> Int {
    box(for: worktreeID).count
  }

  private func box(for worktreeID: WorktreeID) -> Box {
    if let existing = boxes[worktreeID] {
      return existing
    }
    let created = Box()
    boxes[worktreeID] = created
    return created
  }
}
