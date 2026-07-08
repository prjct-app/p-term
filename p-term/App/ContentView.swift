//
//  ContentView.swift
//  p-term
//
//  Created by khoi on 20/1/26.
//

import ComposableArchitecture
import PTermSettingsShared
import SwiftUI
import UniformTypeIdentifiers

#if DEBUG
  private nonisolated let contentRenderLogger = PTermLogger("DetailRender")
#endif

struct ContentView: View {
  @Bindable var store: StoreOf<AppFeature>
  @Bindable var repositoriesStore: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(\.scenePhase) private var scenePhase
  @Environment(GhosttyShortcutManager.self) private var ghosttyShortcuts
  @State private var leftSidebarVisibility: NavigationSplitViewVisibility = .all
  /// Actual rendered width of the right panel column. The HStack resolves the
  /// panel anywhere in its min...max range depending on window width, so the
  /// titlebar reservation must track the real width, not the ideal constant.
  @State private var prjctPanelRenderedWidth: CGFloat = 0

  init(store: StoreOf<AppFeature>, terminalManager: WorktreeTerminalManager) {
    self.store = store
    repositoriesStore = store.scope(state: \.repositories, action: \.repositories)
    terminalsStore = store.scope(state: \.terminals, action: \.terminals)
    self.terminalManager = terminalManager
  }

  var body: some View {
    #if DEBUG
      let _ = contentRenderLogger.info("ContentView.body re-rendered")
    #endif
    return NavigationSplitView(columnVisibility: $leftSidebarVisibility) {
      NativeSideColumn(width: .sidebar) {
        SidebarView(
          store: repositoriesStore, terminalsStore: terminalsStore, terminalManager: terminalManager
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
          SidebarBottomCardView(store: store)
        }
      }
    } detail: {
      HStack(spacing: 0) {
        WorktreeDetailView(store: store, terminalManager: terminalManager)
          .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

        if store.prjctPanel.isVisible && store.prjctPanel.isEnabled {
          Divider()
          prjctPanelColumn
            .frame(
              minWidth: NativeSideColumnWidth.prjctPanel.minWidth,
              idealWidth: NativeSideColumnWidth.prjctPanel.idealWidth,
              maxWidth: NativeSideColumnWidth.prjctPanel.maxWidth,
              maxHeight: .infinity
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .onGeometryChange(for: CGFloat.self) { proxy in
              proxy.size.width
            } action: { newValue in
              prjctPanelRenderedWidth = newValue
            }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationSplitViewStyle(.automatic)
    .dropDestination(for: URL.self) { urls, _ in
      let fileURLs = urls.filter(\.isFileURL)
      guard !fileURLs.isEmpty else { return false }
      store.send(.repositories(.openRepositories(fileURLs)))
      return true
    }
    .disabled(!repositoriesStore.isInitialLoadComplete)
    .onChange(of: scenePhase) { _, newValue in
      store.send(.scenePhaseChanged(newValue))
    }
    .fileImporter(
      isPresented: $repositoriesStore.isOpenPanelPresented.sending(\.setOpenPanelPresented),
      allowedContentTypes: [.folder],
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls):
        store.send(.repositories(.openRepositories(urls)))
      case .failure:
        store.send(
          .repositories(
            .presentAlert(
              title: "Unable to open folders",
              message: "prjct could not read the selected folders."
            )
          )
        )
      }
    }
    .alert($repositoriesStore.scope(state: \.alert, action: \.alert))
    .alert($store.scope(state: \.alert, action: \.alert))
    .sheet(
      item: $store.scope(state: \.deeplinkInputConfirmation, action: \.deeplinkInputConfirmation)
    ) { confirmationStore in
      DeeplinkInputConfirmationView(store: confirmationStore)
    }
    .sheet(
      item: $repositoriesStore.scope(
        state: \.worktreeCreationPrompt, action: \.worktreeCreationPrompt)
    ) { promptStore in
      WorktreeCreationPromptView(store: promptStore)
    }
    .sheet(
      item: $repositoriesStore.scope(
        state: \.repositoryCustomization,
        action: \.repositoryCustomization
      )
    ) { customizationStore in
      RepositoryCustomizationView(store: customizationStore)
    }
    .sheet(
      item: $repositoriesStore.scope(
        state: \.worktreeCustomization,
        action: \.worktreeCustomization
      )
    ) { customizationStore in
      WorktreeCustomizationView(store: customizationStore)
    }
    .sheet(
      item: $repositoriesStore.scope(
        state: \.renameBranchPrompt,
        action: \.renameBranchPrompt
      )
    ) { renameStore in
      RenameBranchView(store: renameStore)
    }
    .focusedSceneAction(\.toggleLeftSidebarAction, enabled: true) {
      withAnimation(.easeOut(duration: 0.2)) {
        leftSidebarVisibility = leftSidebarVisibility == .detailOnly ? .all : .detailOnly
      }
    }
    .focusedSceneAction(
      \.terminateAllTerminalSessionsAction,
      enabled: store.hasAnyTerminalSurface
    ) {
      store.send(.requestTerminateAllTerminalSessions)
    }
    .focusedSceneAction(
      \.revealInSidebarAction,
      enabled: repositoriesStore.selectedWorktreeID != nil
    ) {
      withAnimation(.easeOut(duration: 0.2)) {
        leftSidebarVisibility = .all
      }
      store.send(.repositories(.revealSelectedWorktreeInSidebar))
    }
    .overlay {
      CommandPaletteOverlayHost(
        store: store,
        repositoriesStore: repositoriesStore,
        ghosttyShortcuts: ghosttyShortcuts
      )
    }
    .background(WindowTabbingDisabler())
    .background(
      WindowChromeObserver(
        runtime: terminalManager.ghosttyRuntime,
        trailingTitlebarReservationWidth: trailingTitlebarReservationWidth
      )
    )
    .background(
      WindowTitleHost(
        repositoriesStore: repositoriesStore,
        terminalManager: terminalManager
      )
    )
  }

  /// Width the window titlebar must keep clear on the right so the trailing
  /// toolbar pills sit beside — not over — the panel. Falls back to the ideal
  /// width for the first frame before geometry lands.
  private var trailingTitlebarReservationWidth: CGFloat {
    guard store.prjctPanel.isVisible && store.prjctPanel.isEnabled else { return 0 }
    return prjctPanelRenderedWidth > 0
      ? prjctPanelRenderedWidth
      : NativeSideColumnWidth.prjctPanel.idealWidth
  }

  /// Right-side dashboard content. It is mounted as a real split column beside
  /// the worktree detail so central chrome and content are physically pushed.
  private var prjctPanelColumn: some View {
    PrjctPanelView(
      store: store.scope(state: \.prjctPanel, action: \.prjctPanel),
      onRunCommand: { store.send(.runPrjctCommand($0)) }
    )
  }
}

/// Hosts the command palette overlay so the items build runs in this view's
/// body instead of `ContentView.body`. Per-row sidebar mutations only
/// invalidate this host, leaving ContentView's focused-value closures stable.
private struct CommandPaletteOverlayHost: View {
  let store: StoreOf<AppFeature>
  let repositoriesStore: StoreOf<RepositoriesFeature>
  let ghosttyShortcuts: GhosttyShortcutManager

  var body: some View {
    #if DEBUG
      let _ = contentRenderLogger.info("CommandPaletteOverlayHost.body re-rendered")
    #endif
    // Only build the (O(rows), allocation-heavy) item list when the palette is
    // actually shown. While closed — 99% of the time — this skips the rebuild
    // on every repositories mutation, and reading only `isPresented` keeps the
    // body from re-running on unrelated churn.
    let items =
      store.commandPalette.isPresented
      ? CommandPaletteFeature.commandPaletteItems(
        from: repositoriesStore.state,
        ghosttyCommands: ghosttyShortcuts.commandPaletteEntries,
        scripts: store.allScripts,
        runningScriptIDs: store.runningScriptIDs
      )
      : []
    return CommandPaletteOverlayView(
      store: store.scope(state: \.commandPalette, action: \.commandPalette),
      items: items
    )
  }
}

/// Hosts the `.navigationTitle` modifier so the title computation runs in
/// this view's body. `WindowTitle.compute` reads selection / sidebar.sections
/// fields. Confining the reads here keeps ContentView immune to title-only
/// invalidations from tab renames or section title edits.
private struct WindowTitleHost: View {
  let repositoriesStore: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager

  var body: some View {
    #if DEBUG
      let _ = contentRenderLogger.info("WindowTitleHost.body re-rendered")
    #endif
    return Color.clear
      .navigationTitle(
        WindowTitle.compute(
          repositories: repositoriesStore.state,
          terminalManager: terminalManager
        )
      )
  }
}
