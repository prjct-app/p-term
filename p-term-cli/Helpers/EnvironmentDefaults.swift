import Foundation

/// Typed accessors for p/term environment variables injected into terminal sessions.
nonisolated enum EnvironmentDefaults {
  static var socketPath: String? {
    ProcessInfo.processInfo.environment["P_TERM_SOCKET_PATH"]
  }

  /// Already percent-encoded by the host app.
  static var worktreeID: String? {
    ProcessInfo.processInfo.environment["P_TERM_WORKTREE_ID"]
  }

  static var tabID: String? {
    ProcessInfo.processInfo.environment["P_TERM_TAB_ID"]
  }

  static var surfaceID: String? {
    ProcessInfo.processInfo.environment["P_TERM_SURFACE_ID"]
  }

  /// Already percent-encoded by the host app.
  static var repoID: String? {
    ProcessInfo.processInfo.environment["P_TERM_REPO_ID"]
  }
}
