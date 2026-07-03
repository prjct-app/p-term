import Foundation

extension CloudStatus {
  /// Parses the human-readable `prjct cloud status` output into a `CloudStatus`. The CLI prints a
  /// header line plus indented `Key: value` lines (Authenticated / Linked / Realtime / Pending
  /// events / Last sync); we read those rather than depend on a `--json` flag that may not exist on
  /// every CLI version. Unknown / missing lines fall back to `.unknown`'s defaults.
  nonisolated static func parse(cliOutput: String) -> CloudStatus {
    var status = CloudStatus.unknown

    func boolValue(_ raw: String) -> Bool {
      let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
      return value == "yes" || value == "true" || value == "on"
    }

    for line in cliOutput.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      // The header mentions "paused" when sync is paused for the project.
      if trimmed.lowercased().contains("paused") { status.isPaused = true }
      guard let separator = trimmed.firstRange(of: ":") else { continue }
      let key = trimmed[trimmed.startIndex..<separator.lowerBound]
        .trimmingCharacters(in: .whitespaces)
        .lowercased()
      let value = String(trimmed[separator.upperBound...]).trimmingCharacters(in: .whitespaces)

      switch key {
      case "authenticated": status.isAuthenticated = boolValue(value)
      case "linked": status.isLinked = boolValue(value)
      case "paused": status.isPaused = boolValue(value)
      case "realtime": status.realtime = value.isEmpty ? nil : value
      case "pending events", "pending": status.pendingEvents = Int(value) ?? 0
      case "last sync": status.lastSync = value.isEmpty ? nil : value
      default: continue
      }
    }
    return status
  }
}
