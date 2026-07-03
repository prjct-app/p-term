import Foundation

/// One entry from the project's prjct memory (a decision / gotcha / learning / pattern / spec /
/// context…). Surfacing this natively in p/term is the free, local value that makes the prjct
/// ecosystem *felt* — the terminal knows what the project knows. Cross-machine / team memory is the
/// paid Cloud layer on top.
nonisolated struct MemoryEntry: Identifiable, Equatable, Sendable {
  /// e.g. `mem_471`.
  let id: String
  /// e.g. `decision`, `gotcha`, `learning`, `pattern`, `spec`, `context`.
  let type: String
  let content: String
}
