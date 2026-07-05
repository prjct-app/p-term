import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Testing

@testable import PTermSettingsFeature
@testable import PTermSettingsShared
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

  @Test(.dependencies) func appLaunchedShowsWelcomeWhenNoPersistedSurfaces() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { _ in }
      $0.terminalClient.reapOrphanSessions = { _ in }
      $0.worktreeInfoWatcher.send = { _ in }
    }
    store.exhaustivity = .off

    await store.send(.appLaunched)
    #expect(store.state.isShowingWelcomeScreen == true)
    await store.finish()
  }

  @Test(.dependencies) func appLaunchedDoesNotShowWelcomeWhenPersistedSurfacesExist() async throws {
    let layout = TerminalLayoutSnapshot(
      tabs: [
        TerminalLayoutSnapshot.TabSnapshot(
          id: UUID(),
          title: "tab",
          customTitle: nil,
          icon: nil,
          tintColor: nil,
          layout: .leaf(TerminalLayoutSnapshot.SurfaceSnapshot(id: UUID(), workingDirectory: nil)),
          focusedLeafIndex: 0
        )
      ],
      selectedTabIndex: 0
    )
    let storage = InMemorySettingsFileStorage()
    let payload = try JSONEncoder().encode(["/tmp/repo/wt-feature": layout])
    try storage.save(payload, PTermPaths.layoutsURL)

    try await withDependencies {
      $0.settingsFileStorage = SettingsFileStorage(
        load: { try storage.load($0) },
        save: { try storage.save($0, $1) }
      )
      $0.defaultAppStorage = .inMemory
    } operation: {
      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.send = { _ in }
        $0.terminalClient.reapOrphanSessions = { _ in }
        $0.terminalClient.saveLayoutsWithAgents = { _ in }
        $0.worktreeInfoWatcher.send = { _ in }
      }
      store.exhaustivity = .off

      await store.send(.appLaunched)
      #expect(store.state.isShowingWelcomeScreen == false)
      await store.finish()
    }
  }

  @Test(.dependencies) func lastTerminalClosedShowsWelcomeScreen() async {
    var appState = AppFeature.State()
    appState.isShowingWelcomeScreen = false
    appState.hasAnyTerminalSurface = true
    let store = TestStore(initialState: appState) {
      AppFeature()
    }

    await store.send(.terminalEvent(.terminalHasAnySurfaceChanged(hasAny: false))) {
      $0.hasAnyTerminalSurface = false
      $0.isShowingWelcomeScreen = true
    }
  }

  @Test(.dependencies) func openingFirstTerminalDoesNotForceDismissWelcomeScreen() async {
    var appState = AppFeature.State()
    appState.isShowingWelcomeScreen = true
    appState.hasAnyTerminalSurface = false
    let store = TestStore(initialState: appState) {
      AppFeature()
    }

    await store.send(.terminalEvent(.terminalHasAnySurfaceChanged(hasAny: true))) {
      $0.hasAnyTerminalSurface = true
    }
  }
}
