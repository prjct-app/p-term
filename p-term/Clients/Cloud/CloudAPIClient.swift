import AppKit
import ComposableArchitecture
import Foundation
import PTermSettingsShared

/// The single boundary between p/term and the prjct Cloud service (SOLID: reducers/views never
/// touch the network, the Keychain, or a subprocess directly — only this client does). p/term is a
/// FREE native client: `status` / `isAuthenticated` / `beginLogin` / `logout` are all free; the paid
/// value lives behind the service (sync / team), surfaced as an upsell where the user tries to sync.
struct CloudAPIClient: Sendable {
  /// Cloud state for a project directory (per-project). Free to read.
  var status: @Sendable (_ projectDirectory: URL?) async -> CloudStatus
  /// A `pk_live_*` device key is present locally (signed in on this machine).
  var isAuthenticated: @Sendable () -> Bool
  /// Full sign-in (free): starts a loopback server, opens the browser at `prjct.app/auth/cli?port=`,
  /// captures the device key from the `127.0.0.1/callback`, and persists it. Returns whether it
  /// succeeded.
  var beginLogin: @Sendable () async -> Bool
  /// Persist a `pk_live_*` device key handed over another way (e.g. a `p-term://cloud/auth` deeplink
  /// fallback). Returns false on failure.
  var completeLogin: @Sendable (_ token: String) -> Bool
  /// Sign out: drop the local device key (the CLI reads the same Keychain entry).
  var logout: @Sendable () -> Void

  init(
    status: @escaping @Sendable (_ projectDirectory: URL?) async -> CloudStatus,
    isAuthenticated: @escaping @Sendable () -> Bool,
    beginLogin: @escaping @Sendable () async -> Bool,
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
      do {
        let callback = try await CloudAuthServer.awaitCallback { port in
          guard let url = URL(string: "https://prjct.app/auth/cli?port=\(port)") else { return }
          Task { @MainActor in _ = NSWorkspace.shared.open(url) }
        }
        return CloudKeychain.writeToken(callback.key)
      } catch {
        return false
      }
    },
    completeLogin: { token in CloudKeychain.writeToken(token) },
    logout: { CloudKeychain.deleteToken() }
  )

  static let testValue = CloudAPIClient(
    status: { _ in .unknown },
    isAuthenticated: { false },
    beginLogin: { false },
    completeLogin: { _ in true },
    logout: {}
  )
}
