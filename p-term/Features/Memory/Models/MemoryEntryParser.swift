import Foundation

extension MemoryEntry {
  /// Parses `prjct search "<q>" --json` output. The CLI returns
  /// `{ result: { markdown: "### DECISION\n- `CODE` [mem_471 · decision] <content>\n…" } }`; we
  /// decode the envelope, then pull each `- … [mem_<id> · <type>] <content>` line.
  nonisolated static func parse(searchJSON: String) -> [MemoryEntry] {
    guard let data = searchJSON.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = object["result"] as? [String: Any],
      let markdown = result["markdown"] as? String
    else {
      return []
    }
    return parse(markdown: markdown)
  }

  /// Parses the markdown body's entry lines. Public-to-the-module for direct unit testing.
  nonisolated static func parse(markdown: String) -> [MemoryEntry] {
    var entries: [MemoryEntry] = []
    for rawLine in markdown.split(separator: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard line.hasPrefix("-"),
        let open = line.range(of: "[mem_"),
        let close = line.range(of: "]", range: open.upperBound..<line.endIndex)
      else {
        continue
      }
      // Inside the brackets: "471 · decision".
      let inside = line[open.upperBound..<close.lowerBound]
      let parts = inside.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
      guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
      let content = line[close.upperBound...].trimmingCharacters(in: .whitespaces)
      entries.append(MemoryEntry(id: "mem_\(parts[0])", type: parts[1], content: content))
    }
    return entries
  }
}
