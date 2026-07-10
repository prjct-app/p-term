import AppKit
import ComposableArchitecture
import OrderedCollections
import PTermSettingsShared
import Sharing
import SwiftUI

struct SidebarListView: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  let openRepositoryShortcut: String?
  @FocusState private var isSidebarFocused: Bool
  @Environment(CommandKeyObserver.self) private var commandKeyObserver
  @Shared(.settingsFile) private var settingsFile
  /// Read here purely so SwiftUI re-runs the body (and fires the `.onChange`
  /// below) when the menu writes a new value. The structure compute itself
  /// reads the toggles via local `@Shared` inside the reducer.
  @Shared(.sidebarGroupPinnedRows) private var groupPinnedRows: Bool
  @Shared(.sidebarGroupActiveRows) private var groupActiveRows: Bool
  @Shared(.sidebarNestWorktreesByBranch) private var nestWorktreesByBranch: Bool

  var body: some View {
    let state = store.state
    let structure = state.sidebarStructure
    let selectedWorktreeIDs = state.sidebarSelectedWorktreeIDs
    let pendingSidebarReveal = state.pendingSidebarReveal
    // Only special bucket is Pinned. Everything else is a flat working list
    // with no "Recents" label — you work with those workspaces, not "history".
    let buckets = ClaudeSidebarBuckets(structure: structure)

    // The only legal view-side computation: a trivial join from the
    // reducer-derived `slotByID` against the Cmd state + shortcut overrides.
    // Gated on `isPressed` so the dict is empty when no hints are visible.
    let shortcutHintByID: [Worktree.ID: String]
    if commandKeyObserver.isPressed {
      let overrides = settingsFile.global.shortcutOverrides
      shortcutHintByID = structure.slotByID.compactMapValues { index in
        AppShortcuts.worktreeSelectionShortcutDisplay(atSlot: index, overrides: overrides)
      }
    } else {
      shortcutHintByID = [:]
    }

    // Resolve the single app-wide focused terminal ONCE per list render and
    // thread it down to every session row. Rows used to re-derive it each —
    // an O(tabs) scan per row, and every tab-switch re-ran every row body for
    // a value that is identical across all of them by construction.
    let focusedTab = terminalsStore.terminalTabs.first(where: {
      $0.worktreeID == store.selectedWorktreeID && $0.isSelected
    })
    let focusedTabID = focusedTab?.id
    let focusedSurfaceID = focusedTab?.activeSurfaceID

    return ScrollViewReader { scrollProxy in
      // Plain List — NO selection binding. AppKit List(selection:) draws a
      // selection wash we never want. Active state is title color only
      // (primary = active, secondary = inactive), driven by store.
      List {
        SidebarQuickActionsSection(
          store: store,
          selectedWorktreeIDs: selectedWorktreeIDs,
          openRepositoryShortcut: openRepositoryShortcut
        )
        .moveDisabled(true)

        // Claude: two lists only — Pinned | Recents.
        // Drag workspace between them (= pin / unpin). Hierarchy kept.
        Section {
          SidebarPinnedListBody(
            pinnedIDs: buckets.pinnedIDs,
            structure: structure,
            shortcutHintByID: shortcutHintByID,
            selectedWorktreeIDs: selectedWorktreeIDs,
            focusedTabID: focusedTabID,
            focusedSurfaceID: focusedSurfaceID,
            store: store,
            terminalsStore: terminalsStore,
            terminalManager: terminalManager
          )
        } header: {
          // Pin lives ONLY on the Pinned list title — never on rows / Recents.
          SidebarSoftSectionHeader(title: "Pinned", trailingSystemImage: "pin")
        }

        Section {
          SidebarRecentsListBody(
            openIDs: buckets.openIDs,
            streamSections: buckets.streamSections,
            structure: structure,
            shortcutHintByID: shortcutHintByID,
            selectedWorktreeIDs: selectedWorktreeIDs,
            focusedTabID: focusedTabID,
            focusedSurfaceID: focusedSurfaceID,
            store: store,
            terminalsStore: terminalsStore,
            terminalManager: terminalManager,
            showEmptyDrop: buckets.pinnedIDs.isEmpty == false && !buckets.hasRecentsContent
          )
        } header: {
          SidebarSoftSectionHeader(title: "Recents")
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .focused($isSidebarFocused)
      .frame(minWidth: 220)
      .onChange(of: groupPinnedRows, initial: false) { _, _ in
        store.send(.sidebarGroupingTogglesChanged)
      }
      .onChange(of: groupActiveRows, initial: false) { _, _ in
        store.send(.sidebarGroupingTogglesChanged)
      }
      .onChange(of: nestWorktreesByBranch, initial: false) { _, _ in
        store.send(.sidebarNestByBranchChanged)
      }
      .dropDestination(for: URL.self) { urls, _ in
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }
        store.send(.openRepositories(fileURLs))
        return true
      }
      .onKeyPress { keyPress in
        guard !keyPress.characters.isEmpty else { return .ignored }
        let navigationKeys: Set<KeyEquivalent> = [
          .upArrow, .downArrow, .leftArrow, .rightArrow,
          .home, .end, .pageUp, .pageDown,
        ]
        guard !navigationKeys.contains(keyPress.key) else { return .ignored }
        let hasCommandModifier = keyPress.modifiers.contains(.command)
        if hasCommandModifier { return .ignored }
        guard let worktreeID = store.selectedWorktreeID,
          state.sidebarSelectedWorktreeIDs.count == 1,
          state.sidebarSelectedWorktreeIDs.contains(worktreeID),
          let terminalState = terminalManager.stateIfExists(for: worktreeID)
        else { return .ignored }
        terminalState.focusAndInsertText(keyPress.characters)
        return .handled
      }
      .background(
        // NSOutlineView consumes arrow keys before SwiftUI `onKeyPress` runs.
        SidebarRightArrowMonitor(isSidebarFocused: isSidebarFocused) {
          guard let worktreeID = store.selectedWorktreeID,
            state.sidebarSelectedWorktreeIDs.count == 1,
            state.sidebarSelectedWorktreeIDs.contains(worktreeID),
            let terminalState = terminalManager.stateIfExists(for: worktreeID)
          else { return false }
          terminalState.focusSelectedTab()
          return true
        }
      )
      .task(id: pendingSidebarReveal?.id) {
        await revealPendingSidebarWorktree(pendingSidebarReveal, with: scrollProxy)
      }
    }
  }

  /// SwiftUI's `.onMove` reports offsets in the flat ForEach data array. The
  /// structure exposes `reorderableRepositoryIDs` so we can translate a flat
  /// move into the repository index space the `.repositoriesMoved` reducer
  /// expects. Non-repo sections carry `.moveDisabled(true)` so they can't be
  /// sources of a drag; the destination clamps below.
  private func handleRepositoryMove(
    offsets: IndexSet,
    destination: Int,
    structure: SidebarStructure
  ) {
    let repoIDs = structure.reorderableRepositoryIDs
    guard !repoIDs.isEmpty else { return }
    let sourceFlat = offsets.sorted()
    let sectionsCount = structure.sections.count
    // Map flat section indices to repo indices via SectionID matching. Skip
    // any flat offset that doesn't correspond to a reorderable repo section.
    var repoOffsets = IndexSet()
    for index in sourceFlat where index < sectionsCount {
      let section = structure.sections[index]
      switch section {
      case .repository(let repositoryID, _, _),
        .folder(let repositoryID, _, _),
        .failedRepository(let repositoryID, _, _, _, _):
        if let repoIndex = repoIDs.firstIndex(of: repositoryID) {
          repoOffsets.insert(repoIndex)
        }
      case .highlight, .placeholder, .projectHeader:
        continue
      }
    }
    guard !repoOffsets.isEmpty else { return }
    let clampedDestination = min(max(destination, 0), sectionsCount)
    let repoDestination: Int
    if clampedDestination >= sectionsCount {
      repoDestination = repoIDs.count
    } else {
      let section = structure.sections[clampedDestination]
      switch section {
      case .repository(let repositoryID, _, _),
        .folder(let repositoryID, _, _),
        .failedRepository(let repositoryID, _, _, _, _):
        repoDestination = repoIDs.firstIndex(of: repositoryID) ?? repoIDs.count
      case .highlight, .placeholder, .projectHeader:
        // Dropping above the highlight prefix (or onto a project header)
        // collapses to "before the first repo". Project-relative drops land in
        // Phase 4 Stage 2.
        repoDestination = 0
      }
    }
    store.send(.repositoriesMoved(repoOffsets, repoDestination))
  }

  @MainActor
  private func revealPendingSidebarWorktree(
    _ pendingSidebarReveal: RepositoriesFeature.PendingSidebarReveal?,
    with scrollProxy: ScrollViewProxy
  ) async {
    guard let pendingSidebarReveal else { return }
    // Give SwiftUI time to materialize newly expanded section rows before scrolling.
    await Task.yield()
    await Task.yield()
    isSidebarFocused = true
    withAnimation(.easeOut(duration: 0.2)) {
      scrollProxy.scrollTo(pendingSidebarReveal.worktreeID, anchor: .center)
    }
    store.send(.consumePendingSidebarReveal(pendingSidebarReveal.id))
  }
}

// MARK: - Two lists: Pinned | Recents (Claude)

/// Partition structure into Pinned IDs vs everything else (Recents).
private struct ClaudeSidebarBuckets {
  let pinnedIDs: [Worktree.ID]
  let openIDs: [Worktree.ID]
  let streamSections: [SidebarStructure.Section]
  let isPlaceholder: Bool

  init(structure: SidebarStructure) {
    var pinned: [Worktree.ID] = []
    var open: [Worktree.ID] = []
    var stream: [SidebarStructure.Section] = []
    var placeholder = false
    for section in structure.sections {
      switch section {
      case .highlight(.pinned, let ids):
        pinned = ids
      case .highlight(.active, let ids):
        open = ids
      case .folder, .repository, .failedRepository:
        stream.append(section)
      case .projectHeader:
        continue
      case .placeholder:
        placeholder = true
      }
    }
    self.pinnedIDs = pinned
    self.openIDs = open
    self.streamSections = stream
    self.isPlaceholder = placeholder
  }

  var hasRecentsContent: Bool {
    isPlaceholder || !openIDs.isEmpty || !streamSections.isEmpty
  }
}

/// Shared workspace row: hierarchy workspace → terminals.
private struct SidebarWorkspaceUnitRow: View {
  let rowID: Worktree.ID
  let structure: SidebarStructure
  let shortcutHintByID: [Worktree.ID: String]
  let selectedWorktreeIDs: Set<Worktree.ID>
  let focusedTabID: TerminalTabID?
  let focusedSurfaceID: UUID?
  let leadingInset: CGFloat
  /// true = in Pinned list (children always expanded).
  let inPinnedList: Bool
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager

  var body: some View {
    let repoID = store.state.sidebarItems[id: rowID]?.repositoryID
    SidebarTerminalSessionRowsView(
      rowID: rowID,
      store: store,
      terminalsStore: terminalsStore,
      terminalManager: terminalManager,
      selectedWorktreeIDs: selectedWorktreeIDs,
      isRepositoryRemoving: false,
      shortcutHint: shortcutHintByID[rowID],
      highlightSubtitle: repoID.flatMap { structure.repositoryHighlightByID[$0] },
      focusedTabID: focusedTabID,
      focusedSurfaceID: focusedSurfaceID,
      leadingInset: leadingInset,
      emphasizePin: inPinnedList
    )
  }
}

// MARK: Pinned list

private struct SidebarPinnedListBody: View {
  let pinnedIDs: [Worktree.ID]
  let structure: SidebarStructure
  let shortcutHintByID: [Worktree.ID: String]
  let selectedWorktreeIDs: Set<Worktree.ID>
  let focusedTabID: TerminalTabID?
  let focusedSurfaceID: UUID?
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  @State private var isTargeted = false

  var body: some View {
    Group {
      if pinnedIDs.isEmpty {
        // Quiet empty: still a real drop target, not a dead zone.
        Text("Drop a workspace here to pin")
          .font(AppTypography.caption)
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, minHeight: SidebarNestLayout.rowMinHeight, alignment: .leading)
          .listRowInsets(.leading, 0)
          .listRowInsets(.trailing, SidebarNestLayout.trailingInset)
          .listRowInsets(.vertical, SidebarNestLayout.rowVerticalInset)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .moveDisabled(true)
          .selectionDisabled(true)
          .accessibilityLabel("Pinned is empty. Drop a workspace here to pin.")
      } else {
        // MUST: every pinned workspace keeps full nest (workspace → terminals).
        ForEach(pinnedIDs, id: \.self) { rowID in
          SidebarWorkspaceUnitRow(
            rowID: rowID,
            structure: structure,
            shortcutHintByID: shortcutHintByID,
            selectedWorktreeIDs: selectedWorktreeIDs,
            focusedTabID: focusedTabID,
            focusedSurfaceID: focusedSurfaceID,
            leadingInset: 0,
            inPinnedList: true,
            store: store,
            terminalsStore: terminalsStore,
            terminalManager: terminalManager
          )
        }
      }
    }
    .onDrop(
      of: [SidebarPinDrag.dragType],
      delegate: SidebarPinDropDelegate(isTargeted: $isTargeted) { id in
        guard store.state.sidebarItems[id: id] != nil else { return }
        store.send(.pinWorktree(id))
      }
    )
  }
}

// MARK: Recents list

private struct SidebarRecentsListBody: View {
  let openIDs: [Worktree.ID]
  let streamSections: [SidebarStructure.Section]
  let structure: SidebarStructure
  let shortcutHintByID: [Worktree.ID: String]
  let selectedWorktreeIDs: Set<Worktree.ID>
  let focusedTabID: TerminalTabID?
  let focusedSurfaceID: UUID?
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  var showEmptyDrop: Bool = false
  @State private var isTargeted = false

  /// True when Recents has nothing to show (no open workspaces, no stream).
  private var isEmpty: Bool {
    openProjectGroups.isEmpty && streamSections.isEmpty
  }

  var body: some View {
    Group {
      if isEmpty {
        // Beautiful, functional empty — clear CTA aligned with New/Open craft.
        SidebarRecentsEmptyState(store: store)
      } else {
        // Nest only when it adds information:
        // - 1 worktree per project → `repo → terminals` (no fake intermediate row)
        // - 2+ worktrees in one project → `project → worktree → terminals`
        ForEach(openProjectGroups) { group in
          projectGroupRows(group)
        }

        ForEach(Array(streamSections.enumerated()), id: \.offset) { _, section in
          streamRow(section)
        }
      }

      if showEmptyDrop {
        Color.clear
          .frame(minHeight: 4)
          .listRowInsets(.vertical, 0)
      }
    }
    .onDrop(
      of: [SidebarPinDrag.dragType],
      delegate: SidebarPinDropDelegate(isTargeted: $isTargeted) { id in
        guard let row = store.state.sidebarItems[id: id], row.isPinned else { return }
        store.send(.unpinWorktree(id))
      }
    )
  }

  @ViewBuilder
  private func projectGroupRows(_ group: SidebarWorkingProjectGroup) -> some View {
    // Only introduce a project header when there are multiple worktrees to group.
    // Single worktree: the row IS the project (repo name → terminals). No extra level.
    let multiWorktree = group.rowIDs.count > 1
    Group {
      if multiWorktree {
        SidebarWorkingProjectHeader(group: group)
      }
      ForEach(group.rowIDs, id: \.self) { rowID in
        SidebarWorkspaceUnitRow(
          rowID: rowID,
          structure: structure,
          shortcutHintByID: shortcutHintByID,
          selectedWorktreeIDs: selectedWorktreeIDs,
          focusedTabID: focusedTabID,
          focusedSurfaceID: focusedSurfaceID,
          leadingInset: multiWorktree ? SidebarNestLayout.workspaceUnderProject : 0,
          inPinnedList: false,
          store: store,
          terminalsStore: terminalsStore,
          terminalManager: terminalManager
        )
        .moveDisabled(true)
      }
    }
  }

  private var openProjectGroups: [SidebarWorkingProjectGroup] {
    var groups: [SidebarWorkingProjectGroup] = []
    var indexByRepo: [Repository.ID: Int] = [:]
    for rowID in openIDs {
      guard let item = store.state.sidebarItems[id: rowID], !item.isPinned else { continue }
      let repoID = item.repositoryID
      if let index = indexByRepo[repoID] {
        groups[index].rowIDs.append(rowID)
      } else {
        let tag = structure.repositoryHighlightByID[repoID]
        indexByRepo[repoID] = groups.count
        groups.append(
          SidebarWorkingProjectGroup(
            repositoryID: repoID,
            title: tag?.repoName
              ?? store.state.repositoryName(for: repoID)
              ?? item.workingDirectory.lastPathComponent,
            hostInfo: tag?.hostInfo,
            rowIDs: [rowID]
          )
        )
      }
    }
    return groups
  }

  @ViewBuilder
  private func streamRow(_ section: SidebarStructure.Section) -> some View {
    switch section {
    case .folder(_, let rowID, _):
      if store.state.sidebarItems[id: rowID]?.isPinned != true {
        SidebarWorkspaceUnitRow(
          rowID: rowID,
          structure: structure,
          shortcutHintByID: shortcutHintByID,
          selectedWorktreeIDs: selectedWorktreeIDs,
          focusedTabID: focusedTabID,
          focusedSurfaceID: focusedSurfaceID,
          leadingInset: 0,
          inPinnedList: false,
          store: store,
          terminalsStore: terminalsStore,
          terminalManager: terminalManager
        )
      }
    case .repository(let repositoryID, let groups, let display):
      let rowIDs = groups.flatMap(\.rowIDs).filter {
        store.state.sidebarItems[id: $0]?.isPinned != true
      }
      if !rowIDs.isEmpty {
        // Project header only when this repo has multiple worktrees — never a
        // redundant single-child nest (repo → "Workspace" → Shell).
        let multiWorktree = rowIDs.count > 1
        let group = SidebarWorkingProjectGroup(
          repositoryID: repositoryID,
          title: Repository.sidebarDisplayName(
            custom: display.customTitle, fallback: display.name),
          hostInfo: display.host?.displayAuthority,
          rowIDs: rowIDs
        )
        Group {
          if multiWorktree {
            SidebarWorkingProjectHeader(group: group)
          }
          ForEach(rowIDs, id: \.self) { rowID in
            SidebarWorkspaceUnitRow(
              rowID: rowID,
              structure: structure,
              shortcutHintByID: shortcutHintByID,
              selectedWorktreeIDs: selectedWorktreeIDs,
              focusedTabID: focusedTabID,
              focusedSurfaceID: focusedSurfaceID,
              leadingInset: multiWorktree ? SidebarNestLayout.workspaceUnderProject : 0,
              inPinnedList: false,
              store: store,
              terminalsStore: terminalsStore,
              terminalManager: terminalManager
            )
          }
        }
      }
    case .failedRepository(let repositoryID, let rootURL, let customTitle, let color, let isRemote):
      SidebarFailedRepositoryRowInline(
        repositoryID: repositoryID,
        rootURL: rootURL,
        customTitle: customTitle,
        color: color,
        isRemote: isRemote,
        store: store
      )
    default:
      EmptyView()
    }
  }
}

// MARK: - Recents empty state

/// When Recents has no workspaces — quiet, craft-aligned, actionable.
private struct SidebarRecentsEmptyState: View {
  @Bindable var store: StoreOf<RepositoriesFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("No workspaces yet")
        .font(AppTypography.callout.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)

      Text("Open a project to run terminals and agents here.")
        .font(AppTypography.caption)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)

      Button {
        store.send(.setOpenPanelPresented(true))
      } label: {
        HStack(spacing: SidebarNestLayout.rowSpacing) {
          Image(systemName: "folder.badge.plus")
            .font(AppTypography.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(
              width: AppChromeMetrics.Sidebar.rowIconSize,
              height: AppChromeMetrics.Sidebar.rowIconSize
            )
          Text("Open Workspace")
            .font(AppTypography.callout.weight(.medium))
            .foregroundStyle(.primary)
          Spacer(minLength: 0)
        }
        .frame(minHeight: SidebarNestLayout.rowMinHeight, alignment: .center)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .help("Open a local workspace or folder")
      .accessibilityLabel("Open Workspace")
    }
    .padding(.vertical, 8)
    .padding(.trailing, 4)
    .listRowInsets(.leading, 0)
    .listRowInsets(.trailing, SidebarNestLayout.trailingInset)
    .listRowInsets(.vertical, 6)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .moveDisabled(true)
    .selectionDisabled(true)
  }
}

private struct SidebarWorkingProjectGroup: Identifiable {
  let repositoryID: Repository.ID
  let title: String
  let hostInfo: String?
  var rowIDs: [Worktree.ID]
  var id: Repository.ID { repositoryID }
}

/// Project parent in the nest: quieter than workspace body, always above children.
private struct SidebarWorkingProjectHeader: View {
  let group: SidebarWorkingProjectGroup

  var body: some View {
    HStack(spacing: SidebarNestLayout.rowSpacing) {
      Image(systemName: group.hostInfo == nil ? "folder" : "network")
        .font(AppTypography.caption)
        .foregroundStyle(.secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
      Text(group.title)
        .font(AppTypography.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)
        .lineLimit(1)
      Spacer(minLength: 0)
      if group.rowIDs.count > 1 {
        Text("\(group.rowIDs.count)")
          .font(AppTypography.caption2)
          .monospacedDigit()
          .foregroundStyle(.tertiary)
      }
    }
    .frame(minHeight: SidebarNestLayout.rowMinHeight, alignment: .center)
    .listRowInsets(.leading, 0)
    .listRowInsets(.trailing, SidebarNestLayout.trailingInset)
    .listRowInsets(.vertical, SidebarNestLayout.rowVerticalInset)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .moveDisabled(true)
    .accessibilityLabel(group.title)
    .accessibilityValue(
      group.rowIDs.count == 1
        ? "1 workspace"
        : "\(group.rowIDs.count) workspaces"
    )
  }
}

private struct SidebarFailedRepositoryRowInline: View {
  let repositoryID: Repository.ID
  let rootURL: URL
  let customTitle: String?
  let color: RepositoryColor?
  let isRemote: Bool
  let store: StoreOf<RepositoriesFeature>

  var body: some View {
    let name = Repository.sidebarDisplayName(
      custom: customTitle,
      fallback: Repository.name(for: rootURL.standardizedFileURL)
    )
    FailedRepositoryRow(
      name: name,
      path: rootURL.standardizedFileURL.path(percentEncoded: false),
      removeRepository: {
        store.send(
          isRemote
            ? .requestDeleteRepository(repositoryID)
            : .requestRemoveFailedRepository(repositoryID)
        )
      }
    )
    .listRowBackground(Color.clear)
    .selectionDisabled(true)
    .moveDisabled(true)
  }
}

private struct SidebarFailedRepositorySection: View {
  let repositoryID: Repository.ID
  let rootURL: URL
  let customTitle: String?
  let color: RepositoryColor?
  /// A disconnected SSH repo: route Remove to the remote config store and offer
  /// "Edit Connection…" to fix a bad host/path, rather than the local-roots flow.
  let isRemote: Bool
  let store: StoreOf<RepositoriesFeature>

  private func removeFailedRepository() {
    store.send(isRemote ? .requestDeleteRepository(repositoryID) : .requestRemoveFailedRepository(repositoryID))
  }

  var body: some View {
    let standardizedRootURL = rootURL.standardizedFileURL
    let fallbackName = Repository.name(for: standardizedRootURL)
    let displayName = Repository.sidebarDisplayName(custom: customTitle, fallback: fallbackName)
    let path = standardizedRootURL.path(percentEncoded: false)
    Section {
      FailedRepositoryRow(
        name: displayName,
        path: path,
        removeRepository: removeFailedRepository
      )
      .listRowBackground(Color.clear)
      .selectionDisabled(true)
      .moveDisabled(true)
    } header: {
      RepoSectionHeaderView(
        name: fallbackName,
        customTitle: customTitle,
        color: color,
        isRemoving: false,
        hostInfo: store.state.repositories[id: repositoryID]?.host?.displayAuthority
      )
    }
    .sectionActions {
      // No `+`: the repo isn't loadable, so worktree create is meaningless.
      Menu {
        if isRemote {
          Button("Edit Connection…", systemImage: "wifi") {
            store.send(.requestEditRemoteRepository(repositoryID))
          }
          .help("Edit the SSH server, port, user, or path")
        }
        Button(
          isRemote ? "Stop Tracking SSH Folder…" : "Stop Working Here…",
          systemImage: "folder.badge.minus",
          role: .destructive
        ) {
          removeFailedRepository()
        }
        .help(
          isRemote
            ? "Stop tracking this SSH folder in prjct. Remote files are untouched."
            : "Stop tracking this project in prjct. Files on disk are untouched."
        )
      } label: {
        Image(systemName: "ellipsis")
          .accessibilityLabel("Options")
          .frame(maxHeight: .infinity)
          .contentShape(Rectangle())
      }
      .menuStyle(.secondaryToolbar)
    }
  }
}

// MARK: - Sidebar placeholder.

private struct SidebarPlaceholderView: View {
  var body: some View {
    Section {
      ForEach(0..<6, id: \.self) { _ in
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text("placeholder-title")
              .font(AppTypography.body)
              .lineLimit(1)
              .redacted(reason: .placeholder)
              .shimmer(isActive: true)
            Text("placeholder-detail")
              .font(AppTypography.caption)
              .lineLimit(1)
              .foregroundStyle(.tertiary)
              .redacted(reason: .placeholder)
              .shimmer(isActive: true)
          }
        } icon: {
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(.secondary.opacity(0.18))
            .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
            .redacted(reason: .placeholder)
            .shimmer(isActive: true)
        }
        .labelStyle(.verticallyCentered)
        .listRowInsets(.leading, 0)
        .listRowInsets(.trailing, 4)
        .listRowInsets(.vertical, 4)
      }
    }
    .disabled(true)
  }
}

private struct SidebarRightArrowMonitor: NSViewRepresentable {
  let isSidebarFocused: Bool
  let handle: () -> Bool

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.update(isSidebarFocused: isSidebarFocused, handle: handle)
    context.coordinator.install(host: view)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.update(isSidebarFocused: isSidebarFocused, handle: handle)
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.uninstall()
  }

  @MainActor
  final class Coordinator {
    private var isSidebarFocused = false
    private var handle: () -> Bool = { false }
    private var monitor: Any?

    func update(isSidebarFocused: Bool, handle: @escaping () -> Bool) {
      self.isSidebarFocused = isSidebarFocused
      self.handle = handle
    }

    func install(host: NSView) {
      guard monitor == nil else { return }
      // Local monitors are process-global; scope to the host's window so a
      // stale `@FocusState` in another window can't steal the keystroke.
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak host] event in
        guard event.specialKey == .rightArrow else { return event }
        let userModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        guard event.modifierFlags.isDisjoint(with: userModifiers) else { return event }
        guard let host, event.window === host.window else { return event }
        let consumed = MainActor.assumeIsolated {
          (self?.isSidebarFocused ?? false) && (self?.handle() ?? false)
        }
        return consumed ? nil : event
      }
    }

    func uninstall() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}
