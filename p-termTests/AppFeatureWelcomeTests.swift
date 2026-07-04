import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Testing

@testable import PTermSettingsFeature
@testable import p_term

@MainActor
struct AppFeatureWelcomeTests {
  @Test(.dependencies) func homeActionsToggleWelcomeScreen() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.send(.showWelcomeScreen) {
      $0.isShowingWelcomeScreen = true
    }
    await store.send(.dismissWelcomeScreen) {
      $0.isShowingWelcomeScreen = false
    }
  }

  @Test(.dependencies) func selectingWorktreeDismissesWelcomeScreen() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let worktree = Worktree(
      id: "/tmp/repo/wt-feature",
      name: "feature",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-feature"),
      repositoryRootURL: rootURL
    )
    let repository = Repository(
      id: RepositoryID(rootURL.path(percentEncoded: false)),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [worktree])
    )
    var appState = AppFeature.State(
      repositories: RepositoriesFeature.State(reconciledRepositories: [repository]),
      settings: SettingsFeature.State()
    )
    appState.isShowingWelcomeScreen = true
    let store = TestStore(initialState: appState) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { _ in }
      $0.worktreeInfoWatcher.send = { _ in }
    }
    store.exhaustivity = .off

    await store.send(.repositories(.delegate(.selectedWorktreeChanged(worktree)))) {
      $0.isShowingWelcomeScreen = false
      $0.repositories.$sidebar.withLock { sidebar in
        sidebar.focusedWorktreeID = worktree.id
      }
    }
    await store.finish()
  }
}
