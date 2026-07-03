import Foundation
import Testing

@testable import p_term

struct MemoryEntryParserTests {
  @Test func parsesEntriesFromSearchJSON() {
    let json = """
      {
        "tool": "memory",
        "result": {
          "markdown": "- `D` [mem_471 · decision] fix\\n- `I` [mem_527 · gotcha] bug",
          "entryCount": 2,
          "topic": "palette"
        }
      }
      """
    let entries = MemoryEntry.parse(searchJSON: json)

    #expect(entries.count == 2)
    #expect(entries[0] == MemoryEntry(id: "mem_471", type: "decision", content: "fix"))
    #expect(entries[1].id == "mem_527")
    #expect(entries[1].type == "gotcha")
  }

  @Test func parsesMarkdownDirectly() {
    let markdown = "- `DECL` [mem_8 · learning] Sidebar per-row state lives in RepositoriesFeature."
    let entries = MemoryEntry.parse(markdown: markdown)

    #expect(
      entries == [
        MemoryEntry(id: "mem_8", type: "learning", content: "Sidebar per-row state lives in RepositoriesFeature.")
      ])
  }

  @Test func ignoresNonEntryLinesAndMalformedInput() {
    #expect(MemoryEntry.parse(searchJSON: "not json").isEmpty)
    #expect(MemoryEntry.parse(markdown: "### DECISION\n\nsome prose without a mem marker").isEmpty)
  }
}
