import AppKit
import ComposableArchitecture
import Foundation

/// The single boundary between p/term and the prjct Cloud service (SOLID: reducers/views never
/// touch the network, the Keychain, or a subprocess directly — only this client does). p/term is a
/// FREE native client: `status` / `isAuthenticated` / `beginLogin` / `logout` are all free; the paid
/// value lives behind the service (sync / team), surfaced as an upsell where the user tries to sync.
struct CloudAPIClient: Sendable {
  /// Cloud state for a project directory (per-project). Free to read.
  var status: @Sendable (_ projectDirectory: URL?) async -> CloudStatus
  /// A `pk_live_*` device key is present locally (signed in on this machine).
  var isAuthenticated: @Sendable () -> Bool
  /// Open the browser to sign in (free). The device key returns via the `p-term://cloud/auth`
  /// deeplink, which routes to `completeLogin`.
  var beginLogin: @Sendable () async -> Void
  /// Persist a `pk_live_*` device key captured from the auth callback. Returns false on failure.
  var completeLogin: @Sendable (_ token: String) -> Bool
  /// Sign out: drop the local device key (the CLI reads the same Keychain entry).
  var logout: @Sendable () -> Void

  init(
    status: @escaping @Sendable (_ projectDirectory: URL?) async -> CloudStatus,
    isAuthenticated: @escaping @Sendable () -> Bool,
    beginLogin: @escaping @Sendable () async -> Void,
    completeLogin: @escaping @Sendable (_ token: String) -> Bool,
    logout: @escaping @Sendable () -> Void
  ) {
    self.status = status
    self.isAuthenticated = isAuthenticated
    self.beginLogin = beginLogin
    self.completeLogin = completeLogin
    self.logout = logout
  }
}

extension CloudAPIClient: DependencyKey {
  /// The web sign-in entry point. `client=p-term` tells the web to hand the device key back through
  /// the `p-term://cloud/auth` deeplink (reusing p/term's existing URL-scheme pipeline) instead of a
  /// CLI loopback port.
  static let authWebURL = URL(string: "https://prjct.app/auth/cli?client=p-term")!

  static let liveValue = CloudAPIClient(
    status: { projectDirectory in
      @Dependency(\.shellClient) var shellClient
      let env = URL(fileURLWithPath: "/usr/bin/env")
      guard
        let output = try? await shellClient.runLogin(
          env, ["prjct", "cloud", "status"], projectDirectory, log: false)
      else {
        return .unknown
      }
      return CloudStatus.parse(cliOutput: output.stdout)
    },
    isAuthenticated: { CloudKeychain.readToken() != nil },
    beginLogin: {
      await MainActor.run { NSWorkspace.shared.open(Self.authWebURL) }
    },
    completeLogin: { token in CloudKeychain.writeToken(token) },
    logout: { CloudKeychain.deleteToken() }
  )

  static let testValue = CloudAPIClient(
    status: { _ in .unknown },
    isAuthenticated: { false },
    beginLogin: {},
    completeLogin: { _ in true },
    logout: {}
  )
}
