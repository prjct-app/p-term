import Foundation
import Security

/// Reads / writes the prjct Cloud device API key (`pk_live_*`) in the macOS Keychain, using the
/// SAME service + account the prjct CLI uses (`prjct-cli-auth` / `prjct-cloud`). prjct logging in
/// natively writes here so `prjct` and prjct share one session — sign in once, either tool works.
nonisolated enum CloudKeychain {
  /// Must match `secure-auth-token.ts` in prjct-cli (MACOS_SERVICE / ACCOUNT) or the CLI and the
  /// app stop seeing each other's session.
  static let service = "prjct-cli-auth"
  static let account = "prjct-cloud"

  /// A device key must look like a `pk_live_…` token. Rejects anything else so a
  /// crafted deeplink / loopback callback can't plant an arbitrary string as the
  /// Cloud credential. Defense-in-depth alongside the deeplink confirmation.
  static func isValidTokenFormat(_ token: String) -> Bool {
    token.hasPrefix("pk_live_") && token.count > "pk_live_".count
  }

  static func readToken() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data,
      let token = String(data: data, encoding: .utf8),
      !token.isEmpty
    else {
      return nil
    }
    return token
  }

  @discardableResult
  static func writeToken(_ token: String) -> Bool {
    guard isValidTokenFormat(token) else { return false }
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let data = Data(token.utf8)
    // Upsert: update if present, else add.
    let updateStatus = SecItemUpdate(
      base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if updateStatus == errSecSuccess { return true }
    guard updateStatus == errSecItemNotFound else { return false }
    var addQuery = base
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
  }

  @discardableResult
  static func deleteToken() -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
