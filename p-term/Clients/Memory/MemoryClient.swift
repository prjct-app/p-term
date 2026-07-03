import ComposableArchitecture
import Foundation
import PTermSettingsShared

/// The boundary between p/term and the project's prjct memory (SOLID: the reducer/view never shell
/// out — only this client does). Reads local memory via the `prjct` CLI, so it's free and works
/// offline; the paid Cloud layer is what makes that memory cross-machine / team-shared.
struct MemoryClient: Sendable {
  /// Search the project's memory for `query`. Empty query returns nothing (the surface prompts).
  var search: @Sendable (_ query: String, _ projectDirectory: URL?) async -> [MemoryEntry]

  init(search: @escaping @Sendable (_ query: String, _ projectDirectory: URL?) async -> [MemoryEntry]) {
    self.search = search
  }
}

extension MemoryClient: DependencyKey {
  static let liveValue = MemoryClient(
    search: { query, projectDirectory in
      let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return [] }
      @Dependency(\.shellClient) var shellClient
      let env = URL(fileURLWithPath: "/usr/bin/env")
      guard
        let output = try? await shellClient.runLogin(
          env, ["prjct", "search", trimmed, "--json"], projectDirectory, log: false)
      else {
        return []
      }
      return MemoryEntry.parse(searchJSON: output.stdout)
    }
  )

  static let testValue = MemoryClient(search: { _, _ in [] })
}
