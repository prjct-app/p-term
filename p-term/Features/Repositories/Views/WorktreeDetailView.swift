import AppKit
import ComposableArchitecture
import OrderedCollections
import PTermSettingsFeature
import PTermSettingsShared
import Sharing
import SwiftUI

#if DEBUG
  private nonisolated let detailRenderLogger = PTermLogger("DetailRender")
#endif

struct WorktreeDetailView: View {
  @Bindable var store: StoreOf<AppFeature>
  let terminalManager: WorktreeTerminalManager
  @Shared(.settingsFile) private var settingsFile: SettingsFile
  // Tracks the terminal-content window's fullscreen state for the open-menu toolbar
  // tint; the toolbar itself can't observe it (re-hosted in an accessory window).
  @State private var isToolbarFullScreen = false
  @Environment(\.openWindow) private var openWindow

  private var agentBadgesEnabled: Bool { settingsFile.global.agentPresenceBadgesEnabled }

  var body: some View {
    #if DEBUG
      let _ = Self._printChanges()
      detailRenderLogger.info("WorktreeDetailView.body re-rendered")
    #endif
    return detailBody(state: store.state)
  }

  private func detailBody(state: AppFeature.State) -> some View {
    let repositories = state.repositories
    // Reads the cached slice instead of `sidebarItems[id:]` so per-leaf agent
    // / notification churn on the focused row doesn't invalidate this body.
    let selectedRow = repositories.selectedWorktreeSlice
    let selectedWorktree = repositories.worktree(for: repositories.selectedWorktreeID)
    let selectedWorktreeSummaries = selectedWorktreeSummaries(from: repositories)
    let showsMultiSelectionSummary = shouldShowMultiSelectionSummary(
      repositories: repositories,
      selectedWorktreeSummaries: selectedWorktreeSummaries
    )
    let loadingInfo = loadingInfo(
      for: selectedRow,
      selectedWorktreeID: repositories.selectedWorktreeID,
      repositories: repositories
    )
    // Read here (inside `WorktreeDetailView.body`'s tracked scope) so a tab
    // switch reliably re-invokes `detailBody` and rebuilds the toolbar content
    // below with a fresh value — reading it only inside `ToolbarStatusIslandHost`
    // (several hops into the `ToolbarContent` builder chain) isn't a reliable
    // enough Observation boundary on its own.
    let activeTabID: TerminalTabID? =
      selectedWorktree
      .flatMap { terminalManager.stateIfExists(for: $0.id)?.tabManager.selectedTabId }
    let activeSurfaceID: UUID? =
      if let selectedWorktree, let activeTabID {
        terminalManager.stateIfExists(for: selectedWorktree.id)?.activeSurfaceID(for: activeTabID)
      } else {
        nil
      }
    // ⌘-arrow focus navigation only makes sense with a split; gate it so a
    // single-pane tab doesn't swallow those keys via the menu shortcut.
    let hasSplit: Bool =
      if let selectedWorktree, let activeTabID {
        terminalManager.stateIfExists(for: selectedWorktree.id)?.hasSplit(forTabID: activeTabID)
          ?? false
      } else {
        false
      }
    // Only the stable island inputs here; the live signal is observed in a leaf
    // (see `islandStable` / `ToolbarStatusIslandHost`).
    let islandStable = islandStable(
      state: state,
      selectedWorktree: selectedWorktree,
      selectedRow: selectedRow,
      activeTabID: activeTabID
    )
    let showsToolbarPlaceholder = shouldShowToolbarPlaceholder(
      repositories: repositories,
      loadingInfo: loadingInfo,
      selectedWorktree: selectedWorktree,
      selectedWorktreeSummaries: selectedWorktreeSummaries
    )
    let hasActiveWorktree =
      selectedWorktree != nil
      && loadingInfo == nil
      && !showsMultiSelectionSummary
      && selectedWorktree?.isMissing != true
    // `toolbarNotificationGroupsCache` is observed inside `ToolbarNotificationsPopoverButtonHost`
    // instead; reading it here would re-render the body on every notification.
    let content = detailContent(
      repositories: repositories,
      loadingInfo: loadingInfo,
      selectedWorktree: selectedWorktree,
      selectedSlice: selectedRow,
      selectedWorktreeSummaries: selectedWorktreeSummaries
    )
    .toolbar(removing: .title)
    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    .toolbar {
      if showsToolbarPlaceholder {
        ToolbarPlaceholderContent()
      } else if hasActiveWorktree, let selectedWorktree {
        activeWorktreeToolbarContent(
          state: state,
          selectedWorktree: selectedWorktree,
          selectedRow: selectedRow,
          activeTabID: activeTabID,
          activeSurfaceID: activeSurfaceID,
          islandStable: islandStable
        )
      }
    }
    // Observe fullscreen from the content (main terminal window), then feed it to the
    // toolbar tint above; toolbar content is re-hosted in fullscreen and can't see it.
    .windowFullScreenObserver(isFullScreen: $isToolbarFullScreen)
    let hasRunningRunScript = state.hasRunningRunScript
    // Open / Reveal in Finder reach local paths only; the terminal and search
    // commands stay enabled for a remote worktree (they work over SSH).
    let canOpenLocally = hasActiveWorktree && selectedWorktree?.host == nil
    let resolvedSelection: OpenWorktreeAction? =
      canOpenLocally ? OpenWorktreeAction.availableSelection(store.openActionSelection) : nil
    return applyFocusedActions(
      content: content,
      inputs: FocusedActionInputs(
        hasActiveWorktree: hasActiveWorktree,
        hasSplit: hasSplit,
        canOpenLocally: canOpenLocally,
        hasRunningRunScript: hasRunningRunScript,
        resolvedSelection: resolvedSelection,
        selectedWorktreeID: selectedWorktree?.id
      )
    )
  }

  /// Groups `applyFocusedActions`'s scalar inputs so the function stays under the
  /// parameter-count lint limit.
  private struct FocusedActionInputs {
    let hasActiveWorktree: Bool
    let hasSplit: Bool
    let canOpenLocally: Bool
    let hasRunningRunScript: Bool
    let resolvedSelection: OpenWorktreeAction?
    let selectedWorktreeID: Worktree.ID?
  }

  // Extracted from `detailBody` to stay under the function-body/parameter-count
  // lint limits. Re-derives the same fields `detailBody` already destructures
  // from `state`/`selectedRow` instead of threading them through as separate
  // parameters.
  @ToolbarContentBuilder
  private func activeWorktreeToolbarContent(
    state: AppFeature.State,
    selectedWorktree: Worktree,
    selectedRow: SelectedWorktreeSlice?,
    activeTabID: TerminalTabID?,
    activeSurfaceID: UUID?,
    islandStable: ToolbarStatusIslandStable?
  ) -> some ToolbarContent {
    let repositories = state.repositories
    let toolbarState = WorktreeToolbarState(
      rootURL: selectedWorktree.repositoryRootURL,
      kind: toolbarKind(for: selectedWorktree, selectedRow: selectedRow),
      isRemote: selectedWorktree.host != nil,
      statusToast: repositories.statusToast,
      openActionSelection: state.openActionSelection,
      repoScripts: state.repoScripts,
      globalScripts: state.globalScripts,
      // From the slice instead of `state.runningScriptIDs` so an unrelated
      // `sidebarItems[id:].agents` mutation on the focused row doesn't
      // re-publish this. Same field, observed through the projected slice.
      runningScriptIDs: Set(selectedRow?.runningScripts.ids ?? []),
      branchName: selectedRow?.branchName ?? "",
      toolbarStatusWidgetMode: state.settings.toolbarStatusWidgetMode,
      isPrjctEnabled: state.prjctPanel.isEnabled,
      isPrjctPanelVisible: state.prjctPanel.isVisible,
      isPrjctTerminalAvailable: activeSurfaceID != nil,
      prjctSnapshot: state.prjctPanel.snapshot
    )
    WorktreeToolbarContent(
      toolbarState: toolbarState,
      terminalManager: terminalManager,
      isFullScreen: isToolbarFullScreen,
      repositoriesStore: store.scope(state: \.repositories, action: \.repositories),
      worktreeID: selectedWorktree.id,
      activeTabID: activeTabID,
      islandStable: islandStable,
      terminalsStore: store.scope(state: \.terminals, action: \.terminals),
      onSetStatusWidgetMode: { store.send(.settings(.setToolbarStatusWidgetMode($0))) },
      onOpenCommandPalette: { target in
        store.send(.commandPalette(.present(target: target)))
      },
      onOpenWorktree: { action in
        store.send(.openWorktree(action))
      },
      onOpenActionSelectionChanged: { action in
        store.send(.openActionSelectionChanged(action))
      },
      onRevealInFinder: {
        store.send(.revealInFinder)
      },
      onSelectNotification: selectToolbarNotification,
      appStore: store,
      onSelectAgent: selectFleetAgent,
      onRunScript: { store.send(.runScript) },
      onRunNamedScript: { store.send(.runNamedScript($0, targetWorktreeID: nil)) },
      onStopScript: { store.send(.stopScript($0)) },
      onStopRunScripts: { store.send(.stopRunScripts) },
      onRunPrjctCommand: { store.send(.runPrjctCommand($0)) },
      onManageRepoScripts: {
        let repositoryID = selectedWorktree.repositoryRootURL.path(percentEncoded: false)
        store.send(.settings(.setSelection(.repositoryScripts(repositoryID))))
      },
      onManageGlobalScripts: {
        store.send(.settings(.setSelection(.scripts)))
      },
      onTogglePrjctPanel: {
        store.send(
          .prjctPanel(
            .contextChanged(
              PrjctPanelContext(
                worktree: selectedWorktree,
                tabID: activeTabID,
                surfaceID: activeSurfaceID
              )
            )
          )
        )
        store.send(.prjctPanel(.toggleVisibility))
      }
    )
  }

  private func selectedWorktreeSummaries(
    from repositories: RepositoriesFeature.State
  ) -> [MultiSelectedWorktreeSummary] {
    repositories.sidebarSelectedWorktreeIDs
      .compactMap { worktreeID in
        repositories.selectedRow(for: worktreeID).map {
          MultiSelectedWorktreeSummary(
            id: $0.id,
            repositoryID: $0.repositoryID,
            kind: $0.kind,
            name: $0.name,
            repositoryName: repositories.repositoryName(for: $0.repositoryID)
          )
        }
      }
      .sorted { lhs, rhs in
        let lhsRepository = lhs.repositoryName ?? ""
        let rhsRepository = rhs.repositoryName ?? ""
        if lhsRepository == rhsRepository {
          return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhsRepository.localizedCaseInsensitiveCompare(rhsRepository) == .orderedAscending
      }
  }

  private func shouldShowMultiSelectionSummary(
    repositories: RepositoriesFeature.State,
    selectedWorktreeSummaries: [MultiSelectedWorktreeSummary]
  ) -> Bool {
    !repositories.isShowingArchivedWorktrees
      && selectedWorktreeSummaries.count > 1
  }

  private func shouldShowToolbarPlaceholder(
    repositories: RepositoriesFeature.State,
    loadingInfo: WorktreeLoadingInfo?,
    selectedWorktree: Worktree?,
    selectedWorktreeSummaries: [MultiSelectedWorktreeSummary]
  ) -> Bool {
    if repositories.isShowingArchivedWorktrees {
      return false
    }
    if shouldShowMultiSelectionSummary(
      repositories: repositories,
      selectedWorktreeSummaries: selectedWorktreeSummaries
    ) {
      return false
    }
    if loadingInfo != nil {
      return true
    }
    if selectedWorktree != nil {
      return false
    }
    return !repositories.isInitialLoadComplete
  }

  // Apply `windowTintColorScheme` here, inside the detail body, so that text
  // and icons painted over the tinted window pick the right luminance — but
  // the surrounding `.toolbar { ... }` items keep the system color scheme so
  // they stay readable in fullscreen, where the titlebar paints with system
  // appearance.
  @ViewBuilder
  private func detailContent(
    repositories: RepositoriesFeature.State,
    loadingInfo: WorktreeLoadingInfo?,
    selectedWorktree: Worktree?,
    selectedSlice: SelectedWorktreeSlice?,
    selectedWorktreeSummaries: [MultiSelectedWorktreeSummary]
  ) -> some View {
    Group {
      if repositories.isShowingArchivedWorktrees {
        ArchivedWorktreesDetailView(
          store: store.scope(state: \.repositories, action: \.repositories)
        )
      } else if shouldShowMultiSelectionSummary(
        repositories: repositories,
        selectedWorktreeSummaries: selectedWorktreeSummaries
      ) {
        MultiSelectedWorktreesDetailView(rows: selectedWorktreeSummaries)
      } else if let loadingInfo {
        WorktreeLoadingView(info: loadingInfo)
      } else if let failedRepositoryID = repositories.selectedFailedRepositoryID {
        FailedRepositoryDetailView(
          repositoryID: failedRepositoryID,
          failureMessage: repositories.loadFailuresByID[failedRepositoryID]
        ) {
          store.send(.repositories(.requestRemoveFailedRepository(failedRepositoryID)))
        }
      } else if let selectedWorktree, selectedWorktree.isMissing {
        MissingWorktreeDetailView(worktree: selectedWorktree) {
          guard let repositoryID = repositories.sidebarItems[id: selectedWorktree.id]?.repositoryID
          else { return }
          let target = RepositoriesFeature.DeleteWorktreeTarget(
            worktreeID: selectedWorktree.id,
            repositoryID: repositoryID
          )
          store.send(.repositories(.requestDeleteSidebarItems([target])))
        }
      } else if let selectedWorktree {
        let shouldRunSetupScript = selectedSlice?.lifecycle == .pending
        let shouldFocusTerminal = repositories.shouldFocusTerminal(for: selectedWorktree.id)
        WorktreeTerminalTabsView(
          worktree: selectedWorktree,
          manager: terminalManager,
          terminalsStore: store.scope(state: \.terminals, action: \.terminals),
          shouldRunSetupScript: shouldRunSetupScript,
          forceAutoFocus: shouldFocusTerminal,
          createTab: { store.send(.newTerminal) },
          insertAgentFleetPane: { tabId in
            let hostedView = NSHostingView(
              rootView: AgentFleetPaneView(store: store, onSelect: selectFleetAgent)
            )
            let pane = GenericNativePane(kind: .agentFleet, hostedView: hostedView)
            terminalManager.stateIfExists(for: selectedWorktree.id)?
              .insertNativePane(pane, in: tabId, direction: .right)
          }
        )
        .id(selectedWorktree.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
          if shouldFocusTerminal {
            store.send(.repositories(.consumeTerminalFocus(selectedWorktree.id)))
          }
        }
      } else if !repositories.isInitialLoadComplete {
        DetailPlaceholderView()
      } else {
        EmptyStateView(store: store.scope(state: \.repositories, action: \.repositories))
      }
    }
    .windowTintColorScheme(manager: terminalManager)
  }

  private func applyFocusedActions<Content: View>(
    content: Content,
    inputs: FocusedActionInputs
  ) -> some View {
    content
      .focusedSceneAction(\.openSelectedWorktreeAction, enabled: inputs.canOpenLocally) {
        store.send(.openSelectedWorktree)
      }
      .focusedSceneAction(\.revealInFinderAction, enabled: inputs.canOpenLocally) {
        store.send(.revealInFinder)
      }
      .focusedSceneAction(
        \.openInNewWindowAction, enabled: inputs.hasActiveWorktree, token: inputs.selectedWorktreeID
      ) {
        guard let selectedWorktreeID = inputs.selectedWorktreeID else { return }
        openWindow(value: selectedWorktreeID)
      }
      .focusedSceneValue(\.openActionSelection, inputs.resolvedSelection)
      .focusedSceneAction(\.newTerminalAction, enabled: inputs.hasActiveWorktree) {
        store.send(.newTerminal)
      }
      .focusedAction(\.splitTerminalAction, enabled: inputs.hasActiveWorktree) { direction in
        store.send(.splitTerminal(direction))
      }
      .focusedAction(\.focusSplitAction, enabled: inputs.hasSplit) { direction in
        store.send(.focusSplit(direction))
      }
      .focusedAction(\.closeTabAction, enabled: inputs.hasActiveWorktree) {
        store.send(.closeTab)
      }
      .focusedAction(\.closeSurfaceAction, enabled: inputs.hasActiveWorktree) {
        store.send(.closeSurface)
      }
      .focusedSceneAction(\.startSearchAction, enabled: inputs.hasActiveWorktree) {
        store.send(.startSearch)
      }
      .focusedSceneAction(\.searchSelectionAction, enabled: inputs.hasActiveWorktree) {
        store.send(.searchSelection)
      }
      .focusedSceneAction(\.navigateSearchNextAction, enabled: inputs.hasActiveWorktree) {
        store.send(.navigateSearchNext)
      }
      .focusedSceneAction(\.navigateSearchPreviousAction, enabled: inputs.hasActiveWorktree) {
        store.send(.navigateSearchPrevious)
      }
      .focusedSceneAction(\.endSearchAction, enabled: inputs.hasActiveWorktree) {
        store.send(.endSearch)
      }
      .focusedSceneAction(\.runScriptAction, enabled: inputs.hasActiveWorktree) {
        store.send(.runScript)
      }
      .focusedSceneAction(\.stopRunScriptAction, enabled: inputs.hasRunningRunScript) {
        store.send(.stopRunScripts)
      }
  }

  private func selectToolbarNotification(
    _ worktreeID: Worktree.ID,
    _ notification: WorktreeTerminalNotification
  ) {
    store.send(.repositories(.selectWorktree(worktreeID)))
    if let terminalState = terminalManager.stateIfExists(for: worktreeID) {
      _ = terminalState.focusSurface(id: notification.surfaceID)
    }
  }

  private func selectFleetAgent(_ worktreeID: Worktree.ID, _ surfaceID: UUID) {
    store.send(.repositories(.selectWorktree(worktreeID)))
    if let terminalState = terminalManager.stateIfExists(for: worktreeID) {
      _ = terminalState.focusSurface(id: surfaceID)
    }
  }

  /// Agent fleet button host. Reads `computeAgentFleetGroups()` off the full
  /// app store itself (mirrors `ToolbarNotificationsPopoverButtonHost` below)
  /// so agent-presence churn — which happens constantly during active agent
  /// work — invalidates only this leaf, never `detailBody`'s heavy terminal
  /// split tree.
  fileprivate struct AgentFleetPopoverButtonHost: View {
    let store: StoreOf<AppFeature>
    let onSelect: (Worktree.ID, UUID) -> Void

    var body: some View {
      let groups = store.state.computeAgentFleetGroups()
      if !groups.isEmpty {
        AgentFleetPopoverButton(groups: groups, onSelect: onSelect)
      }
    }
  }

  /// Toolbar notification button host. Reads `toolbarNotificationGroupsCache`
  /// itself so notification churn invalidates only this leaf. `repositoriesStore`
  /// is optional so previews can mount the host without booting a `Store`.
  fileprivate struct ToolbarNotificationsPopoverButtonHost: View {
    let repositoriesStore: StoreOf<RepositoriesFeature>?
    let terminalManager: WorktreeTerminalManager
    let onSelectNotification: (Worktree.ID, WorktreeTerminalNotification) -> Void

    var body: some View {
      if let repositoriesStore {
        let groups = repositoriesStore.toolbarNotificationGroupsCache
        if !groups.isEmpty {
          let unseenWorktreeCount = groups.reduce(0) { $0 + $1.unseenWorktreeCount }
          ToolbarNotificationsPopoverButton(
            groups: groups,
            unseenWorktreeCount: unseenWorktreeCount,
            onSelectNotification: onSelectNotification,
            onDismissAll: {
              for repositoryGroup in groups {
                for worktreeGroup in repositoryGroup.worktrees {
                  terminalManager.stateIfExists(for: worktreeGroup.id)?.dismissAllNotifications()
                }
              }
            }
          )
        }
      }
    }
  }

  /// Remount key for the status island: a change of worktree or active tab is a
  /// hard context switch (remount for a clean slate); intra-tab changes keep the
  /// same identity so the capsule morphs via the leaf store's Observation.
  fileprivate struct TabScopeIdentity: Hashable {
    let worktreeID: Worktree.ID
    let tabID: TerminalTabID?
  }

  fileprivate struct ScriptMenuIdentity: Hashable {
    let rootURL: URL
    let repoFingerprints: [ScriptFingerprint]
    let globalFingerprints: [ScriptFingerprint]
  }

  fileprivate struct ScriptFingerprint: Hashable {
    let id: UUID
    let displayName: String
    let resolvedSystemImage: String
    let resolvedTintColor: RepositoryColor
    let isCommandBlank: Bool

    init(_ script: ScriptDefinition) {
      id = script.id
      displayName = script.displayName
      resolvedSystemImage = script.resolvedSystemImage
      resolvedTintColor = script.resolvedTintColor
      isCommandBlank = script.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  struct WorktreeToolbarState {
    // Folders have no git remote, so the PR payload is scoped to
    // `.git` — this makes "folder with a pull request" unrepresentable.
    enum Kind {
      case git(pullRequest: GithubPullRequest?)
      case folder
    }

    let rootURL: URL
    let kind: Kind
    // Open actions reach local paths only, so the toolbar Open menu is hidden
    // for a remote worktree.
    let isRemote: Bool
    let statusToast: RepositoriesFeature.StatusToast?
    let openActionSelection: OpenWorktreeAction
    let repoScripts: [ScriptDefinition]
    let globalScripts: [ScriptDefinition]
    let runningScriptIDs: Set<UUID>
    let branchName: String
    let toolbarStatusWidgetMode: ToolbarStatusWidgetMode
    let isPrjctEnabled: Bool
    let isPrjctPanelVisible: Bool
    let isPrjctTerminalAvailable: Bool
    let prjctSnapshot: PrjctProjectSnapshot

    var isFolder: Bool {
      if case .folder = kind { true } else { false }
    }

    var pullRequest: GithubPullRequest? {
      if case .git(let pullRequest) = kind { pullRequest } else { nil }
    }

    var allScripts: [ScriptDefinition] {
      .merged(repo: repoScripts, global: globalScripts)
    }

    // Drop globals shadowed by repo IDs (handled by `merged`) and globals with
    // empty commands so half-configured entries don't surface in N repo toolbars.
    var visibleGlobalScripts: [ScriptDefinition] {
      Array(allScripts.dropFirst(repoScripts.count))
        .filter { !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // NSMenu cache key — fingerprint covers only what the toolbar Menu actually renders
    // (display name, icon, tint, has-command). Editing a command body is a no-op for the
    // identity, which avoids per-keystroke menu rebuilds while still catching renames.
    // `fileprivate` because `ScriptMenuIdentity` is fileprivate and the only consumer
    // (`WorktreeToolbarContent`, also fileprivate) lives in this same file.
    fileprivate var scriptMenuIdentity: ScriptMenuIdentity {
      ScriptMenuIdentity(
        rootURL: rootURL,
        repoFingerprints: repoScripts.map(ScriptFingerprint.init),
        globalFingerprints: globalScripts.map(ScriptFingerprint.init),
      )
    }

    /// The first `.run`-kind script, if any.
    var primaryScript: ScriptDefinition? {
      allScripts.primaryScript
    }

    /// Whether any `.run`-kind script is currently running.
    var hasRunningRunScript: Bool {
      allScripts.hasRunningRunScript(in: runningScriptIDs)
    }

    var runScriptHelpText: String {
      @Shared(.settingsFile) var settingsFile
      let display =
        AppShortcuts.runScript.effective(from: settingsFile.global.shortcutOverrides)?.display
        ?? "none"
      return "Run Script (\(display))"
    }

    var stopRunScriptHelpText: String {
      @Shared(.settingsFile) var settingsFile
      let display =
        AppShortcuts.stopRunScript.effective(from: settingsFile.global.shortcutOverrides)?.display
        ?? "none"
      return "Stop Script (\(display))"
    }
  }

  fileprivate struct WorktreeToolbarContent: ToolbarContent {
    let toolbarState: WorktreeToolbarState
    let terminalManager: WorktreeTerminalManager
    let isFullScreen: Bool
    let repositoriesStore: StoreOf<RepositoriesFeature>?
    let worktreeID: Worktree.ID
    /// Stable island inputs (branch/PR/mode) resolved in `detailBody`. The live
    /// per-terminal signal is observed by `ToolbarStatusIslandHost` from the
    /// leaf-scoped tab store below, keeping agent/title churn out of the detail.
    let activeTabID: TerminalTabID?
    let islandStable: ToolbarStatusIslandStable?
    let terminalsStore: StoreOf<TerminalsFeature>?
    let onSetStatusWidgetMode: (ToolbarStatusWidgetMode) -> Void
    let onOpenCommandPalette: (CommandPaletteTarget) -> Void
    let onOpenWorktree: (OpenWorktreeAction) -> Void
    let onOpenActionSelectionChanged: (OpenWorktreeAction) -> Void
    let onRevealInFinder: () -> Void
    let onSelectNotification: (Worktree.ID, WorktreeTerminalNotification) -> Void
    /// Full app store so the fleet host can join `agentPresence` with
    /// `repositories` (`computeAgentFleetGroups()` needs both).
    let appStore: StoreOf<AppFeature>
    let onSelectAgent: (Worktree.ID, UUID) -> Void
    let onRunScript: () -> Void
    let onRunNamedScript: (ScriptDefinition) -> Void
    let onStopScript: (ScriptDefinition) -> Void
    let onStopRunScripts: () -> Void
    let onRunPrjctCommand: (PrjctTerminalCommand) -> Void
    let onManageRepoScripts: () -> Void
    let onManageGlobalScripts: () -> Void
    let onTogglePrjctPanel: () -> Void

    /// Leaf-scoped store for the active tab so the island observes only that
    /// tab's live signal (agents, focused surface). `nil` until a tab resolves.
    private var activeTabStore: StoreOf<TerminalTabFeature>? {
      guard let terminalsStore, let activeTabID else { return nil }
      return terminalsStore.scope(
        state: \.terminalTabs[id: activeTabID],
        action: \.terminalTabs[id: activeTabID]
      )
    }

    var body: some ToolbarContent {
      // Three space-between blocks: [ user ····· island ····· cursor · prjct ].
      // Flexible spacers between the blocks distribute them across the toolbar;
      // the trailing CTAs stay as SEPARATE pills (a ToolbarItemGroup, not one
      // shared HStack/pill) so the editor and prjct buttons don't read as one.

      // Leading: the machine's user identity.
      ToolbarItem {
        ToolbarUserView()
      }

      ToolbarSpacer(.flexible)

      // Center: the status island (+ notifications).
      ToolbarItemGroup {
        ToolbarStatusView(
          toast: toolbarState.statusToast,
          islandStable: islandStable,
          activeTabStore: activeTabStore,
          terminalManager: terminalManager,
          onSetMode: onSetStatusWidgetMode,
          onOpenCommandPalette: onOpenCommandPalette
        )
        // Remount across worktrees AND tab switches (hard context changes);
        // intra-tab agent/pane/title changes flow through the leaf-scoped tab
        // store's Observation so the capsule updates live without a remount.
        .id(TabScopeIdentity(worktreeID: worktreeID, tabID: activeTabID))
        .toolbarTintColorScheme(manager: terminalManager, isFullScreen: isFullScreen)
        ToolbarNotificationsPopoverButtonHost(
          repositoriesStore: repositoriesStore,
          terminalManager: terminalManager,
          onSelectNotification: onSelectNotification
        )
        .toolbarTintColorScheme(manager: terminalManager, isFullScreen: isFullScreen)
        AgentFleetPopoverButtonHost(store: appStore, onSelect: onSelectAgent)
          .toolbarTintColorScheme(manager: terminalManager, isFullScreen: isFullScreen)
      }

      ToolbarSpacer(.flexible)

      // Trailing: editor + prjct + view mode, kept as distinct pills.
      ToolbarItemGroup {
        openMenu(openActionSelection: toolbarState.openActionSelection)
          .disabled(toolbarState.isRemote)
        if toolbarState.isPrjctEnabled {
          PrjctMenu(
            toolbarState: toolbarState,
            onRunPrjctCommand: onRunPrjctCommand,
            onTogglePrjctPanel: onTogglePrjctPanel
          )
        }
        // Paper is the only launched layout mode. Tiles UI is intentionally
        // omitted (code path retained for a possible future return).
      }

    }

    @ViewBuilder
    private func openMenu(openActionSelection: OpenWorktreeAction) -> some View {
      let availableActions = OpenWorktreeAction.availableCases.filter { $0 != .finder }
      let resolved = OpenWorktreeAction.availableSelection(openActionSelection)
      let primarySelection = resolved == .finder ? availableActions.first : resolved
      if let primarySelection {
        ToolbarControlButton {
          onOpenWorktree(primarySelection)
        } icon: {
          OpenWorktreeActionIconView(action: primarySelection)
        } label: {
          Text(primarySelection.labelTitle)
        } menu: {
          // The popup renders as system chrome; escape the toolbar tint below so its
          // rows keep the system appearance instead of the terminal background.
          Group {
            ForEach(availableActions) { action in
              let isDefault = action == primarySelection
              Button {
                onOpenActionSelectionChanged(action)
                onOpenWorktree(action)
              } label: {
                OpenWorktreeActionMenuLabelView(action: action)
              }
              .buttonStyle(.plain)
              .help(openActionHelpText(for: action, isDefault: isDefault))
            }
            Divider()
            Button {
              onRevealInFinder()
            } label: {
              OpenWorktreeActionMenuLabelView(action: .finder)
            }
            .help(
              "Reveal in Finder (\(WorktreeDetailView.resolveShortcutDisplay(for: AppShortcuts.revealInFinder)))"
            )
          }
          .inheritSystemColorScheme()
        }
        .help(openActionHelpText(for: primarySelection, isDefault: true))
        // The colored app icon opts the toolbar item out of AppKit's vibrant foreground,
        // so apply the terminal-aware chrome tint manually to keep the label legible.
        .toolbarTintColorScheme(manager: terminalManager, isFullScreen: isFullScreen)
      }
    }

    private func openActionHelpText(for action: OpenWorktreeAction, isDefault: Bool) -> String {
      guard isDefault else { return action.title }
      return
        "\(action.title) (\(WorktreeDetailView.resolveShortcutDisplay(for: AppShortcuts.openWorktree)))"
    }
  }

  /// Resolves ONLY the stable, low-churn island inputs here in the tracked
  /// `detailBody` scope: branch, pull request, and the pinned mode. The churny
  /// per-terminal signal (agents, focused surface, live title) is deliberately
  /// NOT read here — reading it at `detailBody` level would re-render the whole
  /// detail (including the terminal split view) on every agent/title tick.
  /// `ToolbarStatusIslandHost` observes that live signal from a leaf-scoped tab
  /// store instead, so the churn stays confined to the capsule.
  private func islandStable(
    state: AppFeature.State,
    selectedWorktree: Worktree?,
    selectedRow: SelectedWorktreeSlice?,
    activeTabID: TerminalTabID?
  ) -> ToolbarStatusIslandStable? {
    guard let selectedWorktree, let activeTabID else { return nil }
    let pullRequest: GithubPullRequest? =
      if case .git(let pr) = toolbarKind(for: selectedWorktree, selectedRow: selectedRow) { pr } else { nil }
    return ToolbarStatusIslandStable(
      worktreeID: selectedWorktree.id,
      activeTabID: activeTabID,
      branchName: selectedRow?.branchName ?? "",
      pullRequest: pullRequest,
      pinnedMode: state.settings.toolbarStatusWidgetMode
    )
  }

  private func toolbarKind(
    for selectedWorktree: Worktree,
    selectedRow: SelectedWorktreeSlice?
  ) -> WorktreeToolbarState.Kind {
    guard selectedRow?.isFolder != true else { return .folder }
    guard let pullRequest = selectedRow?.pullRequest else {
      return .git(pullRequest: nil)
    }
    // Only surface the PR when its head branch matches the current
    // worktree, otherwise stale info sticks around after a rename
    // or branch switch.
    let matches = pullRequest.headRefName == nil || pullRequest.headRefName == selectedWorktree.name
    return .git(pullRequest: matches ? pullRequest : nil)
  }

  private func loadingInfo(
    for selectedRow: SelectedWorktreeSlice?,
    selectedWorktreeID: Worktree.ID?,
    repositories: RepositoriesFeature.State
  ) -> WorktreeLoadingInfo? {
    guard let selectedRow else { return nil }
    let repositoryName = repositories.repositoryName(for: selectedRow.repositoryID)
    switch selectedRow.lifecycle {
    case .deleting:
      return WorktreeLoadingInfo(
        name: selectedRow.name,
        repositoryName: repositoryName,
        kind: .removing(isFolder: selectedRow.isFolder)
      )
    case .archiving, .deletingScript:
      // The script runs in a terminal tab, so let the
      // terminal view show through instead of a loading overlay.
      return nil
    case .idle:
      return nil
    case .pending:
      break
    }
    if selectedRow.lifecycle.isPending {
      let pending = repositories.pendingWorktree(for: selectedWorktreeID)
      let progress = pending?.progress
      let displayName = progress?.worktreeName ?? selectedRow.name
      return WorktreeLoadingInfo(
        name: displayName,
        repositoryName: repositoryName,
        kind: .creating(
          WorktreeLoadingInfo.Progress(
            statusTitle: progress?.titleText ?? selectedRow.name,
            statusDetail: progress?.detailText ?? (selectedRow.subtitle ?? ""),
            statusCommand: progress?.commandText,
            statusLines: progress?.liveOutputLines ?? []
          )
        )
      )
    }
    return nil
  }

  static func resolveShortcutDisplay(for shortcut: AppShortcut, fallback: String = "none") -> String {
    @Shared(.settingsFile) var settingsFile
    let display =
      shortcut.effective(from: settingsFile.global.shortcutOverrides)?.display ?? fallback
    return display.isEmpty ? fallback : display
  }
}

// MARK: - Detail placeholder.

private struct FailedRepositoryDetailView: View {
  let repositoryID: Repository.ID
  let failureMessage: String?
  let requestRemove: () -> Void

  var body: some View {
    let path = URL(fileURLWithPath: repositoryID.rawValue).standardizedFileURL.path(
      percentEncoded: false)
    ContentUnavailableView {
      Label("Workspace unavailable", systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.pink)
    } description: {
      VStack(spacing: 6) {
        Text("Restore the project to keep working here, or stop tracking it in prjct.")
        // Diagnostic surface for the underlying load failure (permission denied,
        // missing dir, etc) without disrupting the uniform layout.
        Text(path)
          .monospaced()
          .textSelection(.enabled)
          .help(failureMessage ?? "")
      }
    } actions: {
      Button(
        "Stop Working Here…",
        systemImage: "folder.badge.minus",
        role: .destructive,
        action: requestRemove
      )
      .help("Stop tracking this project in prjct. Files on disk are untouched.")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct MissingWorktreeDetailView: View {
  let worktree: Worktree
  let requestDelete: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("Working directory missing", systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    } description: {
      VStack(spacing: 6) {
        Text("Restore the directory to keep working here, or delete this worktree to clean up.")
        Text(worktree.workingDirectory.path(percentEncoded: false))
          .monospaced()
          .textSelection(.enabled)
      }
    } actions: {
      Button("Delete Worktree…", systemImage: "trash", role: .destructive, action: requestDelete)
        .help("Delete this worktree from prjct.")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct DetailPlaceholderView: View {
  @State private var messageIndex = Int.random(in: 0..<Self.messages.count)

  private static let messages = [
    "Preparing your worktree…",
    "Getting your agents ready…",
    "Syncing git state…",
    "Indexing branches…",
    "Staging your workspace…",
    "Orchestrating terminals…",
    "Spinning up runners…",
    "Warming up shells…",
    "Aligning refs…",
    "Assembling task graph…",
    "Tuning buffers…",
    "Hydrating caches…",
    "Resolving merge conflicts telepathically…",
    "Teaching agents to say less…",
    "Removing \"you're absolutely right!\"…",
    "Evicting polite overcommit…",
    "Reducing agent flattery…",
    "Sharpening code opinions…",
    "Making the bots decisive…",
    "Debouncing Claude Code pleasantries…",
    "Calibrating Codex confidence…",
    "Pruning Claude Code hedges…",
    "Clearing Codex verbosity…",
    "Convincing Copilot to stop guessing…",
    "Telling Cursor to read the error message…",
    "Revoking Gemini's thesaurus access…",
  ]

  var body: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)
      Text(Self.messages[messageIndex])
        .font(AppTypography.title3)
        .foregroundStyle(.secondary)
        .contentTransition(.numericText())
        .shimmer(isActive: true)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      let clock = ContinuousClock()
      while !Task.isCancelled {
        try? await clock.sleep(for: .seconds(1.8))
        withAnimation(.easeInOut(duration: 0.25)) {
          // Pick a random index that differs from the current one.
          var next = Int.random(in: 0..<Self.messages.count - 1)
          if next >= messageIndex { next += 1 }
          messageIndex = next
        }
      }
    }
  }
}

// MARK: - Toolbar placeholder.

private struct ToolbarPlaceholderContent: ToolbarContent {
  var body: some ToolbarContent {
    // No leading item here — the real home button lives at the `ContentView`
    // root and stays mounted through loading, so this skeleton only needs to
    // flank the centered group with symmetric flexible spacers.
    ToolbarSpacer(.flexible)

    ToolbarItemGroup {
      HStack(spacing: 8) {
        Image(systemName: "sun.max.fill")
          .font(AppTypography.callout)
        Text("00:00 – Open Command Palette (⌘P)")
          .font(AppTypography.footnote)
          .monospaced()
      }
      .foregroundStyle(.secondary)
      .padding(.horizontal)
      .redacted(reason: .placeholder)
      .shimmer(isActive: true)
    }

    ToolbarSpacer(.flexible)

    ToolbarItemGroup {
      Button {
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "doc.text")
          Text("VS Code (⌘O)")
        }
      }
      .font(AppTypography.caption)
      .redacted(reason: .placeholder)
      .shimmer(isActive: true)
    }
    ToolbarSpacer(.fixed)

    ToolbarItem {
      Button {
      } label: {
        Label {
          Text("Run")
        } icon: {
          Image(systemName: "play")
        }
        .labelStyle(.titleAndIcon)
      }
      .redacted(reason: .placeholder)
      .shimmer(isActive: true)
    }
  }
}

private struct MultiSelectedWorktreeSummary: Identifiable {
  let id: Worktree.ID
  let repositoryID: Repository.ID
  let kind: SidebarItemFeature.State.Kind
  let name: String
  let repositoryName: String?
}

private struct MultiSelectedWorktreesDetailView: View {
  let rows: [MultiSelectedWorktreeSummary]

  private let visibleRowsLimit = 8

  private var worktreeRows: [MultiSelectedWorktreeSummary] {
    rows.filter { $0.kind == .gitWorktree }
  }

  private var folderRows: [MultiSelectedWorktreeSummary] {
    rows.filter { $0.kind == .folder }
  }

  private var isMixedKindSelection: Bool {
    !worktreeRows.isEmpty && !folderRows.isEmpty
  }

  var body: some View {
    let archiveShortcut = KeyboardShortcut(.delete, modifiers: .command).display
    let deleteShortcut = KeyboardShortcut(.delete, modifiers: [.command, .shift]).display
    VStack(alignment: .leading, spacing: 20) {
      Text("\(rows.count) items selected")
        .font(AppTypography.title3)

      if !worktreeRows.isEmpty {
        selectionSection(
          title: "Worktrees (\(worktreeRows.count))",
          rows: worktreeRows,
          actions: isMixedKindSelection
            ? []
            : [
              "Archive selected (\(archiveShortcut))",
              "Delete selected (\(deleteShortcut))",
              "Right-click any selected worktree to apply actions to all selected worktrees.",
            ]
        )
      }

      if !folderRows.isEmpty {
        selectionSection(
          title: "Folders (\(folderRows.count))",
          rows: folderRows,
          actions: isMixedKindSelection
            ? []
            : [
              "Remove selected from prjct (\(deleteShortcut))",
              "Right-click any selected folder to remove them all from prjct.",
            ]
        )
      }

      if isMixedKindSelection {
        VStack(alignment: .leading, spacing: 6) {
          Label("No bulk action available", systemImage: "exclamationmark.triangle")
            .font(AppTypography.headline)
          Text(
            "Worktrees and folders don't share bulk actions. Deselect "
              + "one kind to archive/delete worktrees or remove folders."
          )
          .font(AppTypography.caption)
          .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func selectionSection(
    title: String,
    rows: [MultiSelectedWorktreeSummary],
    actions: [String]
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(AppTypography.headline)
      ForEach(Array(rows.prefix(visibleRowsLimit))) { row in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(row.name)
            .lineLimit(1)
          if let repositoryName = row.repositoryName, row.kind == .gitWorktree {
            Text(repositoryName)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .font(AppTypography.body)
      }
      if rows.count > visibleRowsLimit {
        Text("+\(rows.count - visibleRowsLimit) more")
          .font(AppTypography.caption)
          .foregroundStyle(.secondary)
      }
      if !actions.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Available actions")
            .font(AppTypography.subheadline)
            .foregroundStyle(.secondary)
          ForEach(actions, id: \.self) { action in
            Text(action)
          }
        }
        .font(AppTypography.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
      }
    }
  }
}

/// Menu with primary action for running scripts in the toolbar.
/// Click runs the default script, stops running scripts, or opens settings;
/// long-press/arrow opens the full script list.
private struct ScriptMenu: View {
  let toolbarState: WorktreeDetailView.WorktreeToolbarState
  let onRunScript: () -> Void
  let onRunNamedScript: (ScriptDefinition) -> Void
  let onStopScript: (ScriptDefinition) -> Void
  let onStopRunScripts: () -> Void
  let onManageRepoScripts: () -> Void
  let onManageGlobalScripts: () -> Void

  private var primaryScript: ScriptDefinition? {
    toolbarState.primaryScript
  }

  var body: some View {
    let hasRunning = toolbarState.hasRunningRunScript
    let icon = hasRunning ? "stop" : (primaryScript?.resolvedSystemImage ?? "play")
    let label = hasRunning ? "Stop" : (primaryScript?.displayName ?? "Run")
    ToolbarControlButton {
      if hasRunning {
        onStopRunScripts()
      } else if primaryScript != nil {
        onRunScript()
      } else if toolbarState.repoScripts.isEmpty, !toolbarState.globalScripts.isEmpty {
        onManageGlobalScripts()
      } else {
        onManageRepoScripts()
      }
    } icon: {
      Image(systemName: icon)
    } label: {
      Text(label)
    } menu: {
      scriptButtons(for: toolbarState.repoScripts)
      let visibleGlobals = toolbarState.visibleGlobalScripts
      if !visibleGlobals.isEmpty {
        if !toolbarState.repoScripts.isEmpty {
          Divider()
        }
        Section("Global") {
          scriptButtons(for: visibleGlobals)
        }
      }
      if !toolbarState.allScripts.isEmpty {
        Divider()
      }
      Button("Manage Workspace Scripts…") {
        onManageRepoScripts()
      }
      .help("Open workspace settings to manage workspace scripts.")
      Button("Manage Global Scripts…") {
        onManageGlobalScripts()
      }
      .help("Open settings to manage global scripts.")
    }
    .help(primaryHelpText(hasRunning: hasRunning))
  }

  @ViewBuilder
  private func scriptButtons(for scripts: [ScriptDefinition]) -> some View {
    ForEach(scripts) { script in
      let isRunning = toolbarState.runningScriptIDs.contains(script.id)
      let hasCommand = !script.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      Button {
        if isRunning {
          onStopScript(script)
        } else {
          onRunNamedScript(script)
        }
      } label: {
        Label {
          Text(isRunning ? "Stop \(script.displayName)" : script.displayName)
        } icon: {
          Image.tintedSymbol(
            isRunning ? "stop" : script.resolvedSystemImage,
            color: script.resolvedTintColor.nsColor,
          )
        }
      }
      .disabled(!isRunning && !hasCommand)
      .help(scriptButtonHelp(script: script, isRunning: isRunning, hasCommand: hasCommand))
    }
  }

  private func scriptButtonHelp(script: ScriptDefinition, isRunning: Bool, hasCommand: Bool)
    -> String
  {
    if isRunning { return "Stop \(script.displayName)." }
    if !hasCommand { return "\"\(script.displayName)\" has no command. Configure it in Settings." }
    return "Run \(script.displayName)."
  }

  private func primaryHelpText(hasRunning: Bool) -> String {
    if hasRunning {
      return toolbarState.stopRunScriptHelpText
    }
    guard primaryScript != nil else {
      return "Configure scripts in Settings."
    }
    return toolbarState.runScriptHelpText
  }
}

/// Leading toolbar block: the machine's GitHub identity (avatar + login). Users
/// on other git hosts have no GitHub login, so this degrades to the system
/// person glyph — the avatar image itself also falls back on any load failure.
private struct ToolbarUserView: View {
  @Dependency(GithubCLIClient.self) private var github
  @State private var username: String?
  @State private var avatarImage: NSImage?
  @State private var didLoad = false

  private var iconSize: CGFloat { AppChromeMetrics.Toolbar.iconSize }

  private var profileURL: URL? {
    username.flatMap { URL(string: "https://github.com/\($0)") }
  }

  var body: some View {
    // Same control component as the editor/prjct buttons so the three toolbar
    // pills are visually identical (icon + label + chevron, one glass capsule).
    ToolbarControlButton(
      primaryAction: { if let profileURL { NSWorkspace.shared.open(profileURL) } },
      icon: { avatar },
      label: { Text(username ?? "Account") }
    ) {
      if let profileURL {
        Link("Open @\(username ?? "") on GitHub", destination: profileURL)
      } else {
        Text("No GitHub account detected")
      }
    }
    .task {
      guard !didLoad else { return }
      didLoad = true
      username = try? await github.authStatus()?.username
      avatarImage = await loadAvatar()
    }
  }

  // The size AND circular shape are baked into the NSImage itself (drawn into a
  // fixed `iconSize` bitmap with a circular clip), so it renders at exactly that
  // size with no reliance on SwiftUI `.frame()` — the same proven technique as
  // `PrjctToolbarMarkView`. Nothing the source image does can blow out the pill.
  @ViewBuilder private var avatar: some View {
    if let avatarImage {
      Image(nsImage: avatarImage)
        .renderingMode(.original)
    } else {
      Image(systemName: "person.crop.circle.fill")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: iconSize, height: iconSize)
        .foregroundStyle(.secondary)
        .symbolRenderingMode(.hierarchical)
    }
  }

  private func loadAvatar() async -> NSImage? {
    guard let username,
      let url = URL(string: "https://github.com/\(username).png?size=128"),
      let (data, _) = try? await URLSession.shared.data(from: url),
      let source = NSImage(data: data)
    else { return nil }
    return Self.circularAvatar(source, side: iconSize)
  }

  /// Draws `source` into a fixed `side`×`side` bitmap clipped to a circle. The
  /// result's `size` IS `side`, so SwiftUI renders it at exactly that size.
  private static func circularAvatar(_ source: NSImage, side: CGFloat) -> NSImage {
    let target = NSImage(size: CGSize(width: side, height: side))
    target.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    NSBezierPath(ovalIn: rect).addClip()
    source.draw(
      in: rect,
      from: NSRect(origin: .zero, size: source.size),
      operation: .sourceOver,
      fraction: 1
    )
    target.unlockFocus()
    return target
  }
}

/// The prjct mark, rasterized to an exact pixel size. The asset is a vector SVG
/// (`preserves-vector-representation`), which renders at its intrinsic size and
/// ignores SwiftUI `.frame()` inside an NSToolbar-backed item — so we draw it
/// into a fixed-size NSImage, the same technique the editor icon uses.
private struct PrjctToolbarMarkView: View {
  let size: CGFloat

  private func rasterizedMark() -> NSImage? {
    guard let mark = NSImage(named: "prjct-mark") else { return nil }
    let target = CGSize(width: size, height: size)
    let raster = NSImage(size: target)
    raster.lockFocus()
    mark.draw(
      in: NSRect(origin: .zero, size: target),
      from: NSRect(origin: .zero, size: mark.size),
      operation: .sourceOver,
      fraction: 1
    )
    raster.unlockFocus()
    return raster
  }

  var body: some View {
    if let raster = rasterizedMark() {
      Image(nsImage: raster)
        .renderingMode(.original)
    } else {
      Image(systemName: "square.dashed")
        .frame(width: size, height: size)
    }
  }
}

private struct PrjctMenu: View {
  let toolbarState: WorktreeDetailView.WorktreeToolbarState
  let onRunPrjctCommand: (PrjctTerminalCommand) -> Void
  let onTogglePrjctPanel: () -> Void

  var body: some View {
    ToolbarControlButton {
      onTogglePrjctPanel()
    } icon: {
      // Same footprint as the Cursor/editor icon. The mark is a vector SVG with
      // `preserves-vector-representation`, which ignores SwiftUI `.frame()` in an
      // NSToolbar-backed item and renders at its intrinsic (huge) size — so we
      // rasterize it to the exact icon size up front, exactly like the editor icon.
      PrjctToolbarMarkView(size: AppChromeMetrics.Toolbar.iconSize)
    } label: {
      Text("prjct")
    } menu: {
      if toolbarState.prjctSnapshot.actions.isEmpty {
        Text("No actions")
      } else {
        Section("Actions") {
          commandButtons(toolbarState.prjctSnapshot.actions)
        }
      }
      if !toolbarState.prjctSnapshot.workflows.isEmpty {
        Divider()
        Section("Workflows") {
          commandButtons(toolbarState.prjctSnapshot.workflows)
        }
      }
      Divider()
      Button(toolbarState.isPrjctPanelVisible ? "Hide Dashboard" : "Show Dashboard") {
        onTogglePrjctPanel()
      }
      .help(toolbarState.isPrjctPanelVisible ? "Hide prjct dashboard" : "Show prjct dashboard")
    }
    .help(toolbarState.isPrjctPanelVisible ? "Hide prjct dashboard" : "Show prjct dashboard")
  }

  @ViewBuilder
  private func commandButtons(_ commands: [PrjctTerminalCommand]) -> some View {
    ForEach(commands) { command in
      Button {
        onRunPrjctCommand(command)
      } label: {
        Label(command.title, systemImage: command.systemImage)
      }
      .disabled(!toolbarState.isPrjctTerminalAvailable)
      .help(toolbarState.isPrjctTerminalAvailable ? (command.detail ?? command.input) : "Select a terminal first.")
    }
  }
}
