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
    let currentSelections = state.sidebarSelections
    let selection = Binding<Set<SidebarSelection>>(
      get: { currentSelections },
      set: { newValue in
        guard newValue != currentSelections else { return }
        store.send(.selectionChanged(newValue, focusTerminal: true))
      }
    )
    let pendingSidebarReveal = state.pendingSidebarReveal
    let firstSessionSectionID = structure.sections.first(where: \.isSessionSection)?.id

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
      List(selection: selection) {
        SidebarQuickActionsSection(
          store: store,
          selectedWorktreeIDs: selectedWorktreeIDs,
          openRepositoryShortcut: openRepositoryShortcut
        )
        .moveDisabled(true)

        ForEach(structure.sections) { section in
          SidebarSessionSectionDispatcher(
            section: section,
            structure: structure,
            showsRecentsHeader: section.id == firstSessionSectionID,
            shortcutHintByID: shortcutHintByID,
            selectedWorktreeIDs: selectedWorktreeIDs,
            focusedTabID: focusedTabID,
            focusedSurfaceID: focusedSurfaceID,
            store: store,
            terminalsStore: terminalsStore,
            terminalManager: terminalManager
          )
        }
        .onMove { offsets, destination in
          handleRepositoryMove(
            offsets: offsets,
            destination: destination,
            structure: structure
          )
        }
      }
      .listStyle(.sidebar)
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

private extension SidebarStructure.Section {
  var isSessionSection: Bool {
    switch self {
    case .folder, .repository, .failedRepository:
      true
    case .highlight, .placeholder, .projectHeader:
      false
    }
  }
}


/// Single switch that turns one `SidebarStructure.Section` into the terminal-first
/// sidebar. The reducer still owns ordering and grouping; this view only changes
/// the information architecture from repositories to sessions.
private struct SidebarSessionSectionDispatcher: View {
  let section: SidebarStructure.Section
  let structure: SidebarStructure
  let showsRecentsHeader: Bool
  let shortcutHintByID: [Worktree.ID: String]
  let selectedWorktreeIDs: Set<Worktree.ID>
  /// The app-wide focused terminal, resolved once by `SidebarListView`.
  let focusedTabID: TerminalTabID?
  let focusedSurfaceID: UUID?
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager

  var body: some View {
    switch section {
    case .placeholder:
      SidebarPlaceholderView()
        .moveDisabled(true)
    case .projectHeader(let projectID, let name, let color, let collapsed, let memberCount):
      SidebarProjectHeaderView(
        projectID: projectID,
        name: name,
        color: color,
        collapsed: collapsed,
        memberCount: memberCount,
        store: store
      )
      .moveDisabled(true)
    case .highlight(let kind, let rowIDs):
      SidebarHighlightSection(
        kind: kind,
        rowIDs: rowIDs,
        store: store,
        terminalsStore: terminalsStore,
        terminalManager: terminalManager,
        selectedWorktreeIDs: selectedWorktreeIDs,
        repositoryHighlightByID: structure.repositoryHighlightByID,
        shortcutHintByID: shortcutHintByID,
        focusedTabID: focusedTabID,
        focusedSurfaceID: focusedSurfaceID
      )
      .moveDisabled(true)
    case .failedRepository(let repositoryID, let rootURL, let customTitle, let color, let isRemote):
      SidebarFailedRepositorySection(
        repositoryID: repositoryID,
        rootURL: rootURL,
        customTitle: customTitle,
        color: color,
        isRemote: isRemote,
        store: store
      )
    case .folder(let repositoryID, let rowID, let display):
      if showsRecentsHeader {
        Section {
          SidebarRecentProjectRow(
            repositoryID: repositoryID,
            display: display,
            rowIDs: [rowID],
            store: store
          )
        } header: {
          SidebarSessionsHeaderView(title: "Recents")
        }
      } else {
        SidebarRecentProjectRow(
          repositoryID: repositoryID,
          display: display,
          rowIDs: [rowID],
          store: store
        )
      }
    case .repository(let repositoryID, let groups, let display):
      SidebarRepositorySessionsSection(
        repositoryID: repositoryID,
        display: display,
        groups: groups,
        showsRecentsHeader: showsRecentsHeader,
        shortcutHintByID: shortcutHintByID,
        selectedWorktreeIDs: selectedWorktreeIDs,
        store: store,
        terminalsStore: terminalsStore,
        terminalManager: terminalManager
      )
    }
  }
}

private struct SidebarRepositorySessionsSection: View {
  let repositoryID: Repository.ID
  let display: SidebarStructure.RepositoryDisplay
  let groups: [SidebarItemGroup]
  let showsRecentsHeader: Bool
  let shortcutHintByID: [Worktree.ID: String]
  let selectedWorktreeIDs: Set<Worktree.ID>
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  var body: some View {
    if showsRecentsHeader {
      Section {
        rows
      } header: {
        SidebarSessionsHeaderView(title: "Recents")
      }
    } else {
      rows
    }
  }

  @ViewBuilder
  private var rows: some View {
    SidebarRecentProjectRow(
      repositoryID: repositoryID,
      display: display,
      rowIDs: groups.flatMap(\.rowIDs),
      store: store
    )
  }
}

private struct SidebarSessionsHeaderView: View {
  let title: String

  var body: some View {
    Text(title)
      .font(AppTypography.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .textCase(nil)
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
      .tag(SidebarSelection.failedRepository(repositoryID))
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
    ForEach(0..<2, id: \.self) { section in
      Section {
        ForEach(0..<3, id: \.self) { _ in
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("placeholder-branch")
                .font(AppTypography.body)
                .lineLimit(1)
                .redacted(reason: .placeholder)
                .shimmer(isActive: true)
              if section == 0 {
                Text("placeholder-detail")
                  .font(AppTypography.footnote)
                  .lineLimit(1)
                  .foregroundStyle(.secondary)
                  .redacted(reason: .placeholder)
                  .shimmer(isActive: true)
              }
            }
          } icon: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(.secondary.opacity(0.22))
              .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
              .redacted(reason: .placeholder)
              .shimmer(isActive: true)
          }
          .labelStyle(.verticallyCentered)
          .listRowInsets(.leading, 0)
          .listRowInsets(.trailing, 4)
          .listRowInsets(.vertical, 6)
        }
      } header: {
        Text(section == 0 ? "Loading" : "Repositories")
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
