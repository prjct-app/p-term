import ComposableArchitecture
import Foundation

/// Global Activity Feed: a capped, newest-first log of cross-worktree events (agent notifications,
/// script results). The reducer stamps each event's id + timestamp from injected dependencies so
/// the ordering/cap logic is deterministically testable.
@Reducer
struct ActivityFeedFeature {
  /// Bound so a long session can't grow the feed without limit; oldest entries fall off.
  static let maxEvents = 200

  @ObservableState
  struct State: Equatable {
    /// Newest first.
    var events: [ActivityEvent] = []
  }

  enum Action: Equatable {
    /// Append an event; the reducer stamps id + timestamp.
    case record(kind: ActivityEvent.Kind, title: String, subtitle: String?, worktreeID: Worktree.ID?)
    case clear
    /// User tapped an event — jump to its worktree if it has one.
    case activate(ActivityEvent)
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    /// Select this worktree in the main window (bringing it forward).
    case jumpToWorktree(Worktree.ID)
  }

  @Dependency(\.uuid) private var uuid
  @Dependency(\.date.now) private var now

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .record(let kind, let title, let subtitle, let worktreeID):
        let event = ActivityEvent(
          id: uuid(),
          timestamp: now,
          kind: kind,
          title: title,
          subtitle: subtitle,
          worktreeID: worktreeID
        )
        state.events.insert(event, at: 0)
        if state.events.count > Self.maxEvents {
          state.events.removeLast(state.events.count - Self.maxEvents)
        }
        return .none

      case .clear:
        state.events.removeAll()
        return .none

      case .activate(let event):
        guard let worktreeID = event.worktreeID else { return .none }
        return .send(.delegate(.jumpToWorktree(worktreeID)))

      case .delegate:
        return .none
      }
    }
  }
}
