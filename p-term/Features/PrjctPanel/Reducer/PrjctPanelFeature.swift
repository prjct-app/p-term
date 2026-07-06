import ComposableArchitecture
import Foundation

@Reducer
struct PrjctPanelFeature {
  @ObservableState
  struct State: Equatable {
    var context = PrjctPanelContext()
    var snapshot: PrjctProjectSnapshot = .notConfigured
    var isVisible = false
    var isLoading = false
    var errorMessage: String?

    var isEnabled: Bool { snapshot.isEnabled }
  }

  enum Action: Equatable {
    case contextChanged(PrjctPanelContext)
    case toggleVisibility
    case setVisibility(Bool)
    case refresh
    case refreshed(PrjctProjectSnapshot)
  }

  @Dependency(PrjctCLIClient.self) private var prjct

  private nonisolated enum CancelID { case refresh }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .contextChanged(let context):
        let previousDirectories = state.context.candidateDirectories
        state.context = context
        state.errorMessage = nil
        if context.isRemote || context.candidateDirectories.isEmpty {
          state.snapshot = .notConfigured
          state.isVisible = false
          state.isLoading = false
          return .cancel(id: CancelID.refresh)
        }
        guard previousDirectories != context.candidateDirectories || !state.snapshot.isEnabled else {
          return .none
        }
        return .send(.refresh)

      case .toggleVisibility:
        guard state.snapshot.isEnabled else { return .none }
        state.isVisible.toggle()
        return state.isVisible ? .send(.refresh) : .none

      case .setVisibility(let isVisible):
        state.isVisible = isVisible && state.snapshot.isEnabled
        return state.isVisible ? .send(.refresh) : .none

      case .refresh:
        guard !state.context.isRemote else {
          state.snapshot = .notConfigured
          state.isVisible = false
          return .none
        }
        let candidates = state.context.candidateDirectories
        state.isLoading = true
        state.errorMessage = nil
        return .run { send in
          await send(.refreshed(prjct.inspect(candidates)))
        }
        .cancellable(id: CancelID.refresh, cancelInFlight: true)

      case .refreshed(let snapshot):
        state.isLoading = false
        state.snapshot = snapshot
        if !snapshot.isEnabled {
          state.isVisible = false
        }
        return .none
      }
    }
  }
}

struct PrjctPanelContext: Equatable, Sendable {
  var worktreeID: Worktree.ID?
  var tabID: TerminalTabID?
  var surfaceID: UUID?
  var workingDirectory: URL?
  var repositoryRootURL: URL?
  var isRemote = false

  var candidateDirectories: [URL] {
    var directories: [URL] = []
    for url in [workingDirectory, repositoryRootURL].compactMap({ $0?.standardizedFileURL }) {
      if !directories.contains(url) {
        directories.append(url)
      }
    }
    return directories
  }
}

extension PrjctPanelContext {
  init(worktree: Worktree, tabID: TerminalTabID? = nil, surfaceID: UUID? = nil) {
    self.init(
      worktreeID: worktree.id,
      tabID: tabID,
      surfaceID: surfaceID,
      workingDirectory: worktree.localWorkingDirectory,
      repositoryRootURL: worktree.host == nil ? worktree.repositoryRootURL : nil,
      isRemote: worktree.host != nil
    )
  }
}
