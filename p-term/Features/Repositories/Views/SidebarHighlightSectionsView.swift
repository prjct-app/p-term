import AppKit
import ComposableArchitecture
import PTermSettingsShared
import SwiftUI
import UniformTypeIdentifiers

/// Two buckets only (Claude):
/// - **Pinned** — workspaces the user pinned (clearly separated)
/// - **Recents** — everything else (open + dormant); never a second Recents
///
/// Flat monochrome rows; only git +/- is colored.
struct SidebarHighlightSection: View {
  let kind: SidebarStructure.HighlightKind
  let rowIDs: [Worktree.ID]
  /// Pinned always shows its header. Active open rows only show "Recents"
  /// when they are the first recents content (not when Recents already started).
  let showsSectionHeader: Bool
  let store: StoreOf<RepositoriesFeature>
  let terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  let selectedWorktreeIDs: Set<Worktree.ID>
  let repositoryHighlightByID: [Repository.ID: SidebarHighlightRepoTag]
  let shortcutHintByID: [Worktree.ID: String]
  let focusedTabID: TerminalTabID?
  let focusedSurfaceID: UUID?

  @State private var isPinDropTargeted = false

  var body: some View {
    if showsSectionHeader {
      Section {
        sectionBody
      } header: {
        sectionHeader
      }
    } else {
      // Continuation of Recents (open workspaces after header already shown,
      // or open workspaces when Recents header lives on a later stream row).
      sectionBody
    }
  }

  @ViewBuilder
  private var sectionHeader: some View {
    // Pin is an action on workspaces, never decoration on section headers.
    SidebarSoftSectionHeader(
      title: kind.listTitle,
      help: kind.helpText,
      isDropTargeted: kind == .pinned && isPinDropTargeted
    )
    .onDrop(
      of: [SidebarPinDrag.dragType],
      delegate: SidebarPinDropDelegate(
        isTargeted: kind == .pinned ? $isPinDropTargeted : .constant(false),
        onDropID: { id in
          if kind == .pinned { pin(id) } else { unpin(id) }
        }
      )
    )
  }

  @ViewBuilder
  private var sectionBody: some View {
    if kind == .pinned {
      pinnedBody
    } else {
      // Open workspaces under Recents — flat, no project nest chrome.
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
          focusedSurfaceID: focusedSurfaceID,
          leadingInset: 0,
          emphasizePin: false
        )
        .onDrop(
          of: [SidebarPinDrag.dragType],
          delegate: SidebarPinDropDelegate(
            isTargeted: .constant(false),
            onDropID: unpin
          )
        )
      }
    }
  }

  @ViewBuilder
  private var pinnedBody: some View {
    // Primary list path is SidebarListView (Pinned | Recents). This body is
    // kept for structure compatibility only.
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
        focusedSurfaceID: focusedSurfaceID,
        leadingInset: 0,
        emphasizePin: true
      )
    }
  }

  private func pin(_ id: Worktree.ID) {
    guard store.state.sidebarItems[id: id] != nil else { return }
    store.send(.pinWorktree(id))
  }

  private func unpin(_ id: Worktree.ID) {
    guard let row = store.state.sidebarItems[id: id], row.isPinned else { return }
    store.send(.unpinWorktree(id))
  }
}

// MARK: - Headers

extension SidebarStructure.HighlightKind {
  /// Only Pinned is a named product section. Active rows sit in the flat list below.
  var listTitle: String {
    switch self {
    case .pinned: "Pinned"
    case .active: ""  // not shown — working list has no section title
    }
  }

  var indicatorColor: Color { .secondary }

  var helpText: String {
    switch self {
    case .pinned: "Pinned workspaces — the only special separation"
    case .active: "Working workspaces"
    }
  }
}

/// Claude-style section label: "Pinned" / "Recents" — quiet, sentence case.
struct SidebarSoftSectionHeader: View {
  let title: String
  var help: String?
  var trailingSystemImage: String?
  var trailingTint: Color?
  var isDropTargeted: Bool = false

  var body: some View {
    HStack(spacing: SidebarNestLayout.rowSpacing) {
      Text(title)
        .font(AppTypography.caption)
        .foregroundStyle(.secondary)
        .textCase(nil)
      Spacer(minLength: 0)
      if let trailingSystemImage {
        Image(systemName: trailingSystemImage)
          .font(AppTypography.caption)
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
    }
    .padding(.top, 4)
    .padding(.bottom, 0)
  }
}

struct SidebarHighlightHeaderDot: View {
  let color: Color
  @Environment(\.pixelLength) private var pixelLength

  var body: some View {
    Circle()
      .fill(Color.secondary.opacity(0.45))
      .overlay(Circle().stroke(Color.secondary.opacity(0.5), lineWidth: pixelLength))
      .frame(width: AppChromeMetrics.Sidebar.statusDotSize, height: AppChromeMetrics.Sidebar.statusDotSize)
      .accessibilityHidden(true)
  }
}

// MARK: - Row

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
  var emphasizePin: Bool = false

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
      leadingInset: leadingInset,
      emphasizePin: emphasizePin
    )
  }
}
