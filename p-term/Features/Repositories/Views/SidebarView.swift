import ComposableArchitecture
import PTermSettingsShared
import Sharing
import SwiftUI

struct SidebarView: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  @Shared(.settingsFile) private var settingsFile

  var body: some View {
    let state = store.state
    let effectiveSelectedRows = state.effectiveSidebarSelectedRows
    let confirmAlert = state.confirmWorktreeAlert
    let archiveTargets =
      effectiveSelectedRows
      .filter { $0.lifecycle == .idle && !$0.isMainWorktree }
      .map {
        RepositoriesFeature.ArchiveWorktreeTarget(
          worktreeID: $0.id,
          repositoryID: $0.repositoryID
        )
      }
    let deleteTargets =
      effectiveSelectedRows
      .filter { $0.lifecycle == .idle }
      .map {
        RepositoriesFeature.DeleteWorktreeTarget(
          worktreeID: $0.id,
          repositoryID: $0.repositoryID
        )
      }
    let openRepo = AppShortcuts.openRepository.effective(from: settingsFile.global.shortcutOverrides)

    return SidebarListView(
      store: store,
      terminalsStore: terminalsStore,
      terminalManager: terminalManager,
      openRepositoryShortcut: openRepo?.display
    )
    .sheet(item: $store.scope(state: \.remoteConnectionForm, action: \.remoteConnectionForm)) { formStore in
      RemoteConnectionFormView(store: formStore)
    }
    .sheet(item: $store.scope(state: \.cloneRepositoryForm, action: \.cloneRepositoryForm)) { formStore in
      CloneRepositoryFormView(store: formStore)
    }
    .focusedSceneAction(
      \.confirmWorktreeAction,
      enabled: confirmAlert != nil,
      token: confirmAlert
    ) {
      if let alert = confirmAlert {
        store.send(.alert(.presented(alert)))
      }
    }
    .focusedAction(
      \.archiveWorktreeAction,
      enabled: !archiveTargets.isEmpty,
      token: archiveTargets
    ) {
      if archiveTargets.count == 1, let target = archiveTargets.first {
        store.send(.requestArchiveWorktree(target.worktreeID, target.repositoryID))
      } else {
        store.send(.requestArchiveWorktrees(archiveTargets))
      }
    }
    .focusedAction(
      \.deleteWorktreeAction,
      enabled: !deleteTargets.isEmpty,
      token: deleteTargets
    ) {
      store.send(.requestDeleteSidebarItems(deleteTargets))
    }
  }
}
