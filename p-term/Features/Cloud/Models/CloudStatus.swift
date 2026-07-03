import Foundation

/// Snapshot of the prjct Cloud state for the current project, as reported by `prjct cloud status`.
/// p/term is a FREE native client of the paid Cloud service: being authenticated + browsing your
/// account is free; the paid value is sync / team / cross-machine memory. This model drives the
/// native surface that presents that state and the upsell at the point of sync.
struct CloudStatus: Equatable, Sendable {
  /// The user is signed in (a `pk_live_*` device key is present + valid).
  var isAuthenticated: Bool
  /// This project is opted into cloud sync (`prjct cloud link`).
  var isLinked: Bool
  /// Sync is paused for this project.
  var isPaused: Bool
  /// Local events not yet mirrored to the cloud.
  var pendingEvents: Int
  /// Realtime channel state, verbatim from the CLI (`connected` / `n/a` / …).
  var realtime: String?
  /// Last successful sync, verbatim from the CLI (`never` / a timestamp).
  var lastSync: String?

  static let unknown = CloudStatus(
    isAuthenticated: false,
    isLinked: false,
    isPaused: false,
    pendingEvents: 0,
    realtime: nil,
    lastSync: nil
  )

  /// The single "what should the surface show" verdict — mirrors the sidebar/toolbar classifier shape.
  enum Presentation: Equatable, Sendable {
    /// Not signed in — offer login (free).
    case signedOut
    /// Signed in but this project isn't syncing — the upsell / link point.
    case signedInUnlinked
    /// Signed in + linked + paused.
    case paused
    /// Actively syncing (or idle-linked) — the paid value is live.
    case syncing(pending: Int)
  }

  var presentation: Presentation {
    guard isAuthenticated else { return .signedOut }
    guard isLinked else { return .signedInUnlinked }
    if isPaused { return .paused }
    return .syncing(pending: pendingEvents)
  }
}
