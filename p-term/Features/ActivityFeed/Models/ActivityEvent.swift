import Foundation

/// A single entry in the global Activity Feed — a chronological, cross-worktree log of
/// "something happened" signals (an agent asked for input, a script finished, a notification
/// arrived). Awareness only: the feed records what happened, it never acts on the agent.
struct ActivityEvent: Identifiable, Equatable, Sendable {
  let id: UUID
  let timestamp: Date
  let kind: Kind
  let title: String
  let subtitle: String?
  /// The worktree the event belongs to, for filtering / jump-to. `nil` for app-wide events.
  let worktreeID: Worktree.ID?

  enum Kind: Equatable, Sendable {
    case notification
    case scriptFinished(success: Bool)
  }

  init(
    id: UUID,
    timestamp: Date,
    kind: Kind,
    title: String,
    subtitle: String? = nil,
    worktreeID: Worktree.ID? = nil
  ) {
    self.id = id
    self.timestamp = timestamp
    self.kind = kind
    self.title = title
    self.subtitle = subtitle
    self.worktreeID = worktreeID
  }
}
