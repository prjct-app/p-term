import Foundation

/// The credentials the prjct Cloud web hands back to the loopback callback after sign-in:
/// `http://127.0.0.1:<port>/callback?key=pk_live_…&user_id=…&email=…&device_id=…` (per the cloud
/// SPEC's auth flow). `key` is the `pk_live_*` device API key; the rest is session metadata.
nonisolated struct CloudAuthCallback: Equatable, Sendable {
  let key: String
  let userId: String?
  let email: String?
  let deviceId: String?

  /// Parses the first line of the loopback HTTP request (`GET /callback?key=… HTTP/1.1`). Returns
  /// nil unless the path is `/callback` and a non-empty `key` is present. Testable in isolation from
  /// the socket.
  nonisolated static func parse(requestLine: String) -> CloudAuthCallback? {
    // "<METHOD> <path-and-query> <HTTP-version>"
    let fields = requestLine.split(separator: " ")
    guard fields.count >= 2 else { return nil }
    let target = String(fields[1])
    guard
      let components = URLComponents(string: target),
      components.path == "/callback"
    else {
      return nil
    }
    let items = components.queryItems ?? []
    func value(_ name: String) -> String? {
      items.first(where: { $0.name == name })?.value.flatMap { $0.isEmpty ? nil : $0 }
    }
    guard let key = value("key") else { return nil }
    return CloudAuthCallback(
      key: key, userId: value("user_id"), email: value("email"), deviceId: value("device_id"))
  }
}
