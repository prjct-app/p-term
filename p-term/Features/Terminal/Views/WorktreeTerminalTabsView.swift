import ComposableArchitecture
import SwiftUI

struct WorktreeTerminalTabsView: View {
  let worktree: Worktree
  let manager: WorktreeTerminalManager
  /// Narrowed terminal-orchestration store. The tab bar scopes per-tab
  /// `TerminalTabFeature` stores via `\.terminalTabs[id:]` from here, so the
  /// tab-bar surface area stays bounded to terminal state.
  let terminalsStore: StoreOf<TerminalsFeature>
  let shouldRunSetupScript: Bool
  let forceAutoFocus: Bool
  /// Rising edge from the sidebar focus token — bumps on every focus request
  /// even when `forceAutoFocus` stays `true`.
  var focusTerminalToken: Int = 0
  let createTab: () -> Void
  /// Splits a native Agent Fleet pane into a tab. `nil` in windows without
  /// app-level store access (see `TerminalTabContextMenuActions`'s doc
  /// comment) — the entry point simply doesn't appear there.
  var insertAgentFleetPane: ((TerminalTabID) -> Void)? = nil
  @State private var windowActivity = WindowActivityState.inactive
  // Reading the chrome appearance env makes SwiftUI invalidate this body when
  // `WindowTintColorScheme` republishes after a Ghostty config reload, so the
  // unfocused-split overlay color tracks system Light/Dark flips.
  @Environment(\.surfaceChromeAppearance) private var chromeAppearance

  var body: some View {
    let state = manager.state(for: worktree) { shouldRunSetupScript }
    // Must precede the body's tab-state read. Deferring to `.task` / `.onAppear`
    // would reintroduce the closed-all flash on first render.
    let _: Void = state.ensureInitialTab(focusing: false)
    let unfocusedSplitOverlay = manager.unfocusedSplitOverlay()
    let _ = chromeAppearance
    VStack(spacing: 0) {
      if !state.shouldHideTabBar {
        TerminalTabBarView(
          manager: state.tabManager,
          terminalState: state,
          terminalsStore: terminalsStore,
          createTab: createTab,
          split: { direction in
            _ = state.performBindingActionOnFocusedSurface(direction.ghosttyBinding)
          },
          canSplit: state.tabManager.selectedTabId.flatMap { state.activeSurfaceID(for: $0) } != nil,
          closeTab: { tabId in
            state.closeTab(tabId)
          },
          closeOthers: { tabId in
            state.closeOtherTabs(keeping: tabId)
          },
          closeToRight: { tabId in
            state.closeTabsToRight(of: tabId)
          },
          closeAll: {
            state.closeAllTabs()
          },
          dismissSplitZoom: { tabId in
            state.dismissSplitZoom(for: tabId)
          },
          renameTab: { tabId, newTitle in
            state.renameTab(tabId, title: newTitle)
          },
          insertAgentFleetPane: insertAgentFleetPane,
        )
        .transition(.move(edge: .top).combined(with: .opacity))
      }
      if let selectedId = state.tabManager.selectedTabId {
        TerminalTabContentStack(tabs: state.tabManager.tabs, selectedTabId: selectedId) { tabId in
          TerminalSplitTreePane(
            tabId: tabId,
            terminalState: state,
            terminalsStore: terminalsStore,
            unfocusedSplitOverlay: unfocusedSplitOverlay
          )
          // Matches the sidebar's inset from the window edge — the terminal
          // content area used to sit flush against every edge (including the
          // bottom, via `.ignoresSafeArea`), which read as inconsistent next
          // to the sidebar's own margin. Applies uniformly to tiles AND
          // paper mode since both render through this one call site.
          //
          // HALF the gap, not the full gap: both layout modes' outermost
          // panes already contribute their own half-gap padding on the edges
          // that face this wrapper (tiled leaves via `PaneChromeMetrics.gap / 2`
          // padding, paper's strip/columns via matching padding in
          // `PaperLayoutView`) — the other half of a normal between-pane gap.
          // Wrapper-half + pane's-own-half = a full gap from the window edge,
          // exactly matching the gap between two adjacent panes instead of
          // doubling up to 1.5x at the boundary.
          .padding(PaneChromeMetrics.gap / 2)
        }
      } else {
        EmptyTerminalPaneView(
          message: "No terminals open",
          actionTitle: "Start New Terminal",
          action: createTab
        )
      }
    }
    .animation(.easeInOut(duration: 0.2), value: state.shouldHideTabBar)
    .background(
      WindowFocusObserverView { activity in
        windowActivity = activity
        state.syncFocus(windowIsKey: activity.isKeyWindow, windowIsVisible: activity.isVisible)
      }
    )
    .onAppear {
      if shouldClaimTerminalFocus {
        claimTerminalFocus(state)
      }
      state.syncFocus(windowIsKey: windowActivity.isKeyWindow, windowIsVisible: windowActivity.isVisible)
    }
    .onChange(of: forceAutoFocus) { _, shouldFocus in
      if shouldFocus {
        claimTerminalFocus(state)
      }
    }
    .onChange(of: focusTerminalToken) { _, _ in
      if forceAutoFocus || shouldClaimTerminalFocus {
        claimTerminalFocus(state)
      }
    }
    .onChange(of: state.tabManager.selectedTabId) { _, _ in
      if shouldClaimTerminalFocus {
        claimTerminalFocus(state)
      }
      state.syncFocus(windowIsKey: windowActivity.isKeyWindow, windowIsVisible: windowActivity.isVisible)
    }
  }

  // Reads `windowActivity` (fed by `WindowFocusObserverView`, scoped to THIS view's own
  // enclosing window via `viewDidMoveToWindow()`) rather than the app-wide `NSApp.keyWindow` —
  // required so a background window doesn't think it's focused just because some other prjct
  // window is currently key.
  //
  // `forceAutoFocus` overrides the "don't steal from NSTableView" gate: a deliberate
  // sidebar activation must put the caret in the terminal on the first click.
  private var shouldClaimTerminalFocus: Bool {
    forceAutoFocus || windowActivity.canAutoFocusTerminal
  }

  /// Focus the selected surface, retrying briefly while Ghostty attaches.
  /// One-shot onAppear often races surface creation; retries cover that without
  /// requiring multi-click workarounds from the user.
  private func claimTerminalFocus(_ state: WorktreeTerminalState) {
    state.ensureInitialTab(focusing: true)
    state.focusSelectedTab()
    Task { @MainActor in
      for nanoseconds: UInt64 in [50_000_000, 120_000_000, 250_000_000, 500_000_000] {
        try? await Task.sleep(nanoseconds: nanoseconds)
        state.focusSelectedTab()
      }
    }
  }
}

/// Reads the per-tab projection so SwiftUI invalidates whenever the tab's surface
/// set or focus changes. `WorktreeTerminalState.trees` and `focusedSurfaceIdByTab`
/// are `@ObservationIgnored`, so without this dependency Cmd+D / Cmd+W would not
/// re-render until something else (a worktree switch) forced a body recompute.
private struct TerminalSplitTreePane: View {
  let tabId: TerminalTabID
  let terminalState: WorktreeTerminalState
  let terminalsStore: StoreOf<TerminalsFeature>
  let unfocusedSplitOverlay: (fill: Color?, opacity: Double)

  var body: some View {
    let projection = terminalsStore.terminalTabs[id: tabId]
    let _ = projection?.surfaceIDs
    let _ = projection?.activeSurfaceID
    // Touch generation so SwiftUI rebuilds the tree when a same-UUID surface view is swapped under it.
    let _ = projection?.surfaceGeneration
    let mode = terminalState.layoutMode(for: tabId)
    // The mode toggle used to live here as a floating overlay button; it's
    // now the "View" picker in the window toolbar (next to the editor/prjct
    // pills) instead, so this view is just the switch with no chrome of its
    // own — see `WorktreeToolbarContent.viewModeMenu` in `WorktreeDetailView.swift`.
    if let sourcePaneID = terminalState.gitDiffPanelPaneID(in: tabId) {
      HSplitView {
        layoutView(mode: mode, projection: projection)
          .frame(minWidth: 320)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        GitDiffPanelView(
          worktreeURL: terminalState.worktreeURL,
          sourceDirectoryURL: sourceDirectoryURL(for: sourcePaneID),
          sourcePaneID: sourcePaneID
        )
        .id(gitDiffPanelIdentity(for: sourcePaneID))
        .frame(
          minWidth: AppChromeMetrics.SidePanel.diffMinWidth,
          idealWidth: AppChromeMetrics.SidePanel.diffIdealWidth,
          maxWidth: .infinity
        )
        .frame(maxHeight: .infinity)
      }
      .animation(.default, value: sourcePaneID)
    } else {
      layoutView(mode: mode, projection: projection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  @ViewBuilder
  private func layoutView(
    mode: TabLayoutMode,
    projection: TerminalTabFeature.State?
  ) -> some View {
    switch mode {
    case .tiles:
      TerminalSplitTreeAXContainer(
        tree: terminalState.splitTree(for: tabId),
        terminalState: terminalState,
        tabState: projection,
        activeSurfaceID: terminalState.activeSurfaceID(for: tabId),
        unfocusedSplitOverlay: unfocusedSplitOverlay,
        action: { operation in
          terminalState.performSplitOperation(operation, in: tabId)
        }
      )
    case .paper(let layout):
      PaperLayoutView(
        tabId: tabId,
        terminalState: terminalState,
        tabState: projection,
        layout: layout,
        activeSurfaceID: terminalState.activeSurfaceID(for: tabId),
        unfocusedSplitOverlay: unfocusedSplitOverlay
      )
    }
  }

  private func sourceDirectoryURL(for paneID: UUID) -> URL? {
    guard let pane = terminalState.pane(withID: paneID, in: tabId),
      case .terminal(let surface) = pane.content
    else { return nil }
    let pwd = surface.bridge.state.pwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !pwd.isEmpty else { return nil }
    return URL(fileURLWithPath: pwd, isDirectory: true)
  }

  private func gitDiffPanelIdentity(for paneID: UUID) -> String {
    sourceDirectoryURL(for: paneID)?.path(percentEncoded: false)
      ?? "\(paneID.uuidString):\(terminalState.worktreeURL.path(percentEncoded: false))"
  }
}
