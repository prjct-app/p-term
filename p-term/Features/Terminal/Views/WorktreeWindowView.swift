import ComposableArchitecture
import SwiftUI

/// Content for the secondary, detail-only worktree window (`WindowGroup(for: WorktreeID.self)`
/// in `PTermApp.swift`). Resolves its fixed `worktreeID` once and mounts
/// `WorktreeTerminalTabsView` directly — it never reads or writes
/// `repositories.selectedWorktreeID`, so it can't fight the main window over selection.
struct WorktreeWindowView: View {
  let worktreeID: WorktreeID
  @Bindable var repositoriesStore: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(OpenWindowRegistry.self) private var openWindowRegistry
  // Minted once per window instance and reused for both register/deregister calls so a
  // deregister can never accidentally target a different instance's registration.
  @State private var instanceID = OpenWindowRegistry.WindowInstanceID()

  var body: some View {
    Group {
      if let worktree = repositoriesStore.state.worktree(for: worktreeID) {
        WorktreeTerminalTabsView(
          worktree: worktree,
          manager: terminalManager,
          terminalsStore: terminalsStore,
          shouldRunSetupScript: false,
          forceAutoFocus: true,
          createTab: {
            // Bypasses the `.newTerminal` TCA action, which implicitly targets
            // `repositories.selectedWorktreeID` (the main window's selection) — this window
            // has a fixed worktree independent of that selection, so it dispatches straight to
            // the manager the same way `TerminalClient.send(.createTab(...))` would.
            terminalManager.handleCommand(.createTab(worktree, runSetupScriptIfNew: false))
          }
        )
        .navigationTitle(worktree.name)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
      } else {
        MissingWorktreeWindowPlaceholder()
      }
    }
    // Registers/deregisters this window instance with `OpenWindowRegistry` so the sidebar can
    // show a "N windows open" group for `worktreeID`. Only secondary windows register — the
    // main window's implicit view of a worktree never counts toward the group threshold.
    .onAppear { openWindowRegistry.registerOpened(instanceID, for: worktreeID) }
    .onDisappear { openWindowRegistry.registerClosed(instanceID, for: worktreeID) }
  }
}

/// Shown when the window's worktree was deleted/archived out from under it while open —
/// deliberately handled here rather than deferred, since a crash on worktree deletion with a
/// secondary window open would be an obvious regression to hit in normal use.
private struct MissingWorktreeWindowPlaceholder: View {
  var body: some View {
    ContentUnavailableView {
      Label("Worktree no longer available", systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    } description: {
      Text("This worktree was removed. You can close this window.")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
