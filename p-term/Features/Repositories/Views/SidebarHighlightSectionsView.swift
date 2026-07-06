import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

/// Pinned / Active highlight section renderer. Receives an already-ordered
/// row ID list from `SidebarStructure` and just lays it out; no per-leaf
/// classification or sort runs here.
struct SidebarHighlightSection: View {
  let kind: SidebarStructure.HighlightKind
  let rowIDs: [Worktree.ID]
  let store: StoreOf<RepositoriesFeature>
  let terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  let selectedWorktreeIDs: Set<Worktree.ID>
  let repositoryHighlightByID: [Repository.ID: SidebarHighlightRepoTag]
  /// Hint string to render in the row's trailing slot, keyed by `Worktree.ID`.
  /// Empty when Cmd isn't pressed; the caller builds it once for the whole
  /// composed hotkey order.
  let shortcutHintByID: [Worktree.ID: String]
  /// The app-wide focused terminal, resolved once by `SidebarListView`.
  let focusedTabID: TerminalTabID?
  let focusedSurfaceID: UUID?

  var body: some View {
    Section {
      if kind == .active {
        ForEach(activeProjectGroups) { group in
          SidebarActiveProjectHeader(group: group)
          ForEach(group.rowIDs, id: \.self) { rowID in
            SidebarHighlightRow(
              rowID: rowID,
              store: store,
              terminalsStore: terminalsStore,
              terminalManager: terminalManager,
              selectedWorktreeIDs: selectedWorktreeIDs,
              repositoryHighlightByID: repositoryHighlightByID,
              shortcutHint: shortcutHintByID[rowID],
              focusedTabID: focusedTabID,
              focusedSurfaceID: focusedSurfaceID,
              leadingInset: SidebarNestLayout.indentStep
            )
          }
        }
      } else {
        ForEach(rowIDs, id: \.self) { rowID in
          SidebarHighlightRow(
            rowID: rowID,
            store: store,
            terminalsStore: terminalsStore,
            terminalManager: terminalManager,
            selectedWorktreeIDs: selectedWorktreeIDs,
            repositoryHighlightByID: repositoryHighlightByID,
            shortcutHint: shortcutHintByID[rowID],
            focusedTabID: focusedTabID,
            focusedSurfaceID: focusedSurfaceID
          )
        }
      }
    } header: {
      HStack(spacing: 4) {
        Text(kind.title)
        SidebarHighlightHeaderDot(color: kind.indicatorColor)
      }
    }
  }

  private var activeProjectGroups: [SidebarActiveProjectGroup] {
    var groups: [SidebarActiveProjectGroup] = []
    var indexByRepositoryID: [Repository.ID: Int] = [:]
    for rowID in rowIDs {
      guard let row = store.state.sidebarItems[id: rowID] else { continue }
      let repositoryID = row.repositoryID
      if let index = indexByRepositoryID[repositoryID] {
        groups[index].rowIDs.append(rowID)
      } else {
        let highlight = repositoryHighlightByID[repositoryID]
        indexByRepositoryID[repositoryID] = groups.count
        groups.append(
          SidebarActiveProjectGroup(
            repositoryID: repositoryID,
            title: highlight?.repoName ?? row.resolvedSidebarTitle ?? row.branchName,
            color: highlight?.repoColor,
            hostInfo: highlight?.hostInfo,
            rowIDs: [rowID]
          )
        )
      }
    }
    return groups
  }
}

private struct SidebarActiveProjectGroup: Identifiable {
  let repositoryID: Repository.ID
  let title: String
  let color: RepositoryColor?
  let hostInfo: String?
  var rowIDs: [Worktree.ID]

  var id: Repository.ID { repositoryID }
}

private struct SidebarActiveProjectHeader: View {
  let group: SidebarActiveProjectGroup

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: group.hostInfo == nil ? "folder" : "wifi")
        .font(AppTypography.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
      Text(group.title)
        .font(AppTypography.body.weight(.semibold))
        .foregroundStyle(group.color?.color ?? .primary)
        .lineLimit(1)
      Spacer(minLength: 0)
      if group.rowIDs.count > 1 {
        Text("\(group.rowIDs.count)")
          .font(AppTypography.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    .listRowInsets(.leading, 0)
    .listRowInsets(.trailing, 4)
    .listRowInsets(.vertical, 5)
    .moveDisabled(true)
    .accessibilityLabel(group.title)
  }
}

extension SidebarStructure.HighlightKind {
  var indicatorColor: Color {
    switch self {
    case .pinned: .orange
    case .active: .blue
    }
  }
}

/// Colored dot shown after a highlight section title and reused after each
/// bucket label in the per-repo hoist summary line.
struct SidebarHighlightHeaderDot: View {
  let color: Color
  @Environment(\.pixelLength) private var pixelLength

  var body: some View {
    Circle()
      .fill(color.opacity(0.6))
      .overlay(Circle().stroke(color, lineWidth: pixelLength))
      .frame(width: AppChromeMetrics.Sidebar.statusDotSize, height: AppChromeMetrics.Sidebar.statusDotSize)
      .accessibilityHidden(true)
  }
}

/// Single highlight-section row. Resolves its repo identity via per-leaf
/// scope so observation stays bounded to the leaf, then forwards into
/// `SidebarItemRow` for the actual draw. Extracted as a struct so each row
/// gets its own SwiftUI identity (per "view subviews as structs").
private struct SidebarHighlightRow: View {
  let rowID: SidebarItemID
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  let selectedWorktreeIDs: Set<Worktree.ID>
  let repositoryHighlightByID: [Repository.ID: SidebarHighlightRepoTag]
  let shortcutHint: String?
  let focusedTabID: TerminalTabID?
  let focusedSurfaceID: UUID?
  var leadingInset: CGFloat = 0

  var body: some View {
    let highlight =
      store.scope(state: \.sidebarItems[id: rowID], action: \.sidebarItems[id: rowID])
      .flatMap { repositoryHighlightByID[$0.state.repositoryID] }
    SidebarTerminalSessionRowsView(
      rowID: rowID,
      store: store,
      terminalsStore: terminalsStore,
      terminalManager: terminalManager,
      selectedWorktreeIDs: selectedWorktreeIDs,
      isRepositoryRemoving: false,
      shortcutHint: shortcutHint,
      highlightSubtitle: highlight,
      focusedTabID: focusedTabID,
      focusedSurfaceID: focusedSurfaceID,
      leadingInset: leadingInset
    )
  }
}
