import ComposableArchitecture
import Foundation

/// Drives the native Memory surface: a debounced search over the project's prjct memory. SOLID —
/// the reducer orchestrates, `MemoryClient` does the shelling. Free + local; the Cloud layer is
/// what makes this memory cross-machine / team-shared.
@Reducer
struct MemoryFeature {
  @ObservableState
  struct State: Equatable {
    var query = ""
    var entries: [MemoryEntry] = []
    var isSearching = false
    /// The focused project's working directory — memory is per-project. Set by the parent.
    var projectDirectory: URL?
  }

  enum Action: Equatable {
    case queryChanged(String)
    case search
    case loaded([MemoryEntry])
  }

  @Dependency(MemoryClient.self) private var memory
  @Dependency(\.continuousClock) private var clock

  private enum CancelID { case search }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .queryChanged(let query):
        state.query = query
        // Debounce keystrokes; the latest edit cancels the in-flight timer.
        return .run { send in
          try await clock.sleep(for: .milliseconds(250))
          await send(.search)
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)

      case .search:
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
          state.entries = []
          state.isSearching = false
          return .none
        }
        state.isSearching = true
        let projectDirectory = state.projectDirectory
        return .run { send in
          await send(.loaded(memory.search(query, projectDirectory)))
        }

      case .loaded(let entries):
        state.isSearching = false
        state.entries = entries
        return .none
      }
    }
  }
}
