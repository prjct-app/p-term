import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

/// The stable, low-churn slice of the status island's inputs — branch, pull
/// request, and pinned mode. Resolved in `WorktreeDetailView.detailBody`'s
/// tracked scope. The live per-terminal signal (agents, focused surface, title)
/// is NOT here; it's observed by `ToolbarStatusIslandHost` from a leaf-scoped
/// tab store so agent/title churn never re-renders the detail body.
struct ToolbarStatusIslandStable: Equatable {
  let worktreeID: Worktree.ID
  let activeTabID: TerminalTabID
  let branchName: String
  let pullRequest: GithubPullRequest?
  let pinnedMode: ToolbarStatusWidgetMode
}

struct ToolbarStatusView: View {
  let toast: RepositoriesFeature.StatusToast?
  /// Stable island inputs; `nil` while no active worktree tab is resolved.
  let islandStable: ToolbarStatusIslandStable?
  /// Leaf-scoped store for the active tab, so the island's live signal
  /// (agents, focused surface) observes only this tab.
  let activeTabStore: StoreOf<TerminalTabFeature>?
  let terminalManager: WorktreeTerminalManager
  let onSetMode: (ToolbarStatusWidgetMode) -> Void
  let onOpenCommandPalette: (CommandPaletteTarget) -> Void

  var body: some View {
    Group {
      switch toast {
      case .inProgress(let message):
        HStack(spacing: AppChromeMetrics.Toolbar.contentSpacing) {
          ProgressView()
            .controlSize(.small)
            .frame(width: AppChromeMetrics.Toolbar.iconSize, height: AppChromeMetrics.Toolbar.iconSize)
          Text(message)
            .font(AppTypography.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppChromeMetrics.Toolbar.horizontalPadding)
        .padding(.vertical, AppChromeMetrics.Toolbar.verticalPadding)
        .frame(minHeight: AppChromeMetrics.Toolbar.controlHeight)
        .transition(.opacity)
      case .success(let message):
        HStack(spacing: AppChromeMetrics.Toolbar.contentSpacing) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .frame(width: AppChromeMetrics.Toolbar.iconSize, height: AppChromeMetrics.Toolbar.iconSize)
            .accessibilityHidden(true)
          Text(message)
            .font(AppTypography.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppChromeMetrics.Toolbar.horizontalPadding)
        .padding(.vertical, AppChromeMetrics.Toolbar.verticalPadding)
        .frame(minHeight: AppChromeMetrics.Toolbar.controlHeight)
        .transition(.opacity)
      case nil:
        if let islandStable {
          ToolbarStatusIslandHost(
            stable: islandStable,
            activeTabStore: activeTabStore,
            terminalManager: terminalManager,
            onSetMode: onSetMode,
            onOpenCommandPalette: onOpenCommandPalette
          )
          .transition(.opacity)
        }
      }
    }
    .animation(.easeInOut(duration: 0.2), value: toast)
  }
}

/// Assembles the island's full `Inputs` from the stable slice plus the live,
/// leaf-scoped per-terminal signal. When the active tab's store is resolved it
/// hands off to `ToolbarStatusIslandResolvedHost` (which observes it via
/// `@Bindable`); otherwise it renders the island with no agent activity so the
/// branch / PR / time still show.
private struct ToolbarStatusIslandHost: View {
  let stable: ToolbarStatusIslandStable
  let activeTabStore: StoreOf<TerminalTabFeature>?
  let terminalManager: WorktreeTerminalManager
  let onSetMode: (ToolbarStatusWidgetMode) -> Void
  let onOpenCommandPalette: (CommandPaletteTarget) -> Void

  var body: some View {
    if let activeTabStore {
      ToolbarStatusIslandResolvedHost(
        stable: stable,
        tabStore: activeTabStore,
        terminalManager: terminalManager,
        onSetMode: onSetMode,
        onOpenCommandPalette: onOpenCommandPalette
      )
    } else {
      ToolbarStatusIslandView(
        inputs: ToolbarStatusIslandInputsBuilder.build(
          stable: stable,
          agents: [],
          activeSurfaceID: nil,
          activeTabItem: nil
        ),
        onSetMode: onSetMode,
        onOpenCommandPalette: {
          onOpenCommandPalette(
            CommandPaletteTarget(worktreeID: stable.worktreeID, tabID: stable.activeTabID, surfaceID: nil)
          )
        }
      )
    }
  }
}

/// Live leaf: `@Bindable` on the active tab's scoped store means reading
/// `tabStore.agents` / `tabStore.activeSurfaceID` here registers Observation on
/// exactly this tab, so the capsule updates the instant the focused pane's
/// agent activity or focus changes — without touching the detail body. The tab
/// item (title / blocking-script flags) comes from the observable manager and
/// is likewise read only in this leaf.
private struct ToolbarStatusIslandResolvedHost: View {
  let stable: ToolbarStatusIslandStable
  @Bindable var tabStore: StoreOf<TerminalTabFeature>
  let terminalManager: WorktreeTerminalManager
  let onSetMode: (ToolbarStatusWidgetMode) -> Void
  let onOpenCommandPalette: (CommandPaletteTarget) -> Void

  private var activeTabItem: TerminalTabItem? {
    terminalManager.stateIfExists(for: stable.worktreeID)?
      .tabManager.tabs.first(where: { $0.id == stable.activeTabID })
  }

  private var agents: [AgentPresenceFeature.AgentInstance] {
    let all = tabStore.agents
    // Scope to the focused pane so a split's other panes don't leak activity;
    // fall back to every agent on the tab when no surface is resolved yet.
    guard let surfaceID = tabStore.activeSurfaceID else { return all }
    return all.filter { $0.surfaceID == surfaceID }
  }

  var body: some View {
    ToolbarStatusIslandView(
      inputs: ToolbarStatusIslandInputsBuilder.build(
        stable: stable,
        agents: agents,
        activeSurfaceID: tabStore.activeSurfaceID,
        activeTabItem: activeTabItem
      ),
      onSetMode: onSetMode,
      onOpenCommandPalette: {
        onOpenCommandPalette(
          CommandPaletteTarget(
            worktreeID: stable.worktreeID,
            tabID: stable.activeTabID,
            surfaceID: tabStore.activeSurfaceID
          )
        )
      }
    )
  }
}

private enum ToolbarStatusIslandInputsBuilder {
  static func build(
    stable: ToolbarStatusIslandStable,
    agents: [AgentPresenceFeature.AgentInstance],
    activeSurfaceID: UUID?,
    activeTabItem: TerminalTabItem?
  ) -> ToolbarStatusSignal.Inputs {
    ToolbarStatusSignal.Inputs(
      activeTabAgents: agents,
      activeTabIsRunningScript: (activeTabItem?.isBlockingScript ?? false)
        && !(activeTabItem?.isBlockingScriptCompleted ?? true),
      activeTabTitle: activeTabItem?.displayTitle ?? "",
      pullRequest: stable.pullRequest,
      branchName: stable.branchName,
      pinnedMode: stable.pinnedMode,
      now: .now
    )
  }
}

/// Sun/moon-by-hour styling, reused by the island's `.time` fallback case.
struct ToolbarTimeStyle {
  let icon: String
  let color: Color

  static func style(for hour: Int) -> ToolbarTimeStyle {
    switch hour {
    case 6..<12:
      ToolbarTimeStyle(icon: "sunrise.fill", color: .orange)
    case 12..<17:
      ToolbarTimeStyle(icon: "sun.max.fill", color: .yellow)
    case 17..<21:
      ToolbarTimeStyle(icon: "sunset.fill", color: .pink)
    default:
      ToolbarTimeStyle(icon: "moon.stars.fill", color: .indigo)
    }
  }
}
