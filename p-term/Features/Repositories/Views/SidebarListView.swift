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
      case .repository(let repositoryID, _),
        .folder(let repositoryID, _),
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
      case .repository(let repositoryID, _),
        .folder(let repositoryID, _),
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

private struct SidebarQuickActionsSection: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  let selectedWorktreeIDs: Set<Worktree.ID>
  let openRepositoryShortcut: String?

  var body: some View {
    Section {
      SidebarPrimaryActionRow(
        title: "New session",
        systemImage: "plus",
        isProminent: true
      ) {
        store.send(.createRandomWorktree)
      }
      .help("Start a new terminal session")

      Menu {
        Button {
          store.send(.setOpenPanelPresented(true))
        } label: {
          Label("Local folder…", systemImage: "laptopcomputer")
        }
        .help("Open a local repository or folder (\(openRepositoryShortcut ?? "none"))")

        Button {
          store.send(.requestAddRemoteRepository)
        } label: {
          Label("SSH folder…", systemImage: "wifi")
        }
        .help("Open a folder on an SSH host")

        Divider()

        Button {
          store.send(.requestCloneRepository)
        } label: {
          Label("Clone repository…", systemImage: "square.and.arrow.down.on.square")
        }
        .help("Clone a remote repository into a local folder")
      } label: {
        SidebarPrimaryActionLabel(title: "Open source", systemImage: "externaldrive.connected.to.line.below")
      }
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .help("Open a local folder, SSH folder, or clone")

      if let customizationTarget {
        SidebarPrimaryActionRow(title: "Customize", systemImage: "slider.horizontal.3") {
          switch customizationTarget {
          case .repository(let id):
            store.send(.requestCustomizeRepository(id))
          case .worktree(let worktreeID, let repositoryID):
            store.send(.requestCustomizeWorktree(worktreeID, repositoryID))
          }
        }
        .help("Customize the selected session")
      }

      Menu {
        Button {
          store.send(.refreshWorktrees)
        } label: {
          Label("Reload sessions", systemImage: "arrow.clockwise")
        }
        if selectedWorktreeIDs.count == 1, let worktreeID = selectedWorktreeIDs.first {
          Button {
            store.send(.revealHoistedWorktreeInSidebar(worktreeID))
          } label: {
            Label("Reveal selected", systemImage: "scope")
          }
        }
      } label: {
        SidebarPrimaryActionLabel(title: "More", systemImage: "chevron.down")
      }
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .help("More session actions")
    }
  }

  private enum CustomizationTarget {
    case repository(Repository.ID)
    case worktree(Worktree.ID, Repository.ID)
  }

  private var customizationTarget: CustomizationTarget? {
    guard selectedWorktreeIDs.count == 1,
      let worktreeID = selectedWorktreeIDs.first,
      let row = store.state.selectedRow(for: worktreeID)
    else { return nil }
    if row.isMainWorktree && !row.isFolder {
      return .repository(row.repositoryID)
    }
    return .worktree(worktreeID, row.repositoryID)
  }
}

private struct SidebarPrimaryActionRow: View {
  let title: String
  let systemImage: String
  var isProminent = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      SidebarPrimaryActionLabel(title: title, systemImage: systemImage, isProminent: isProminent)
    }
    .buttonStyle(.plain)
  }
}

private struct SidebarPrimaryActionLabel: View {
  let title: String
  let systemImage: String
  var isProminent = false

  var body: some View {
    Label {
      Text(title)
        .font(AppTypography.body.weight(isProminent ? .semibold : .regular))
        .lineLimit(1)
    } icon: {
      Image(systemName: systemImage)
        .font(AppTypography.body.weight(.medium))
        .foregroundStyle(isProminent ? .primary : .secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    }
    .labelStyle(.verticallyCentered)
    .foregroundStyle(.primary)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      if isProminent {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(.quaternary)
      }
    }
    .contentShape(.interaction, .rect)
    .listRowInsets(.leading, 0)
    .listRowInsets(.trailing, 4)
    .listRowInsets(.vertical, 2)
    .typeSelectEquivalent("")
  }
}

struct SidebarTerminalSessionRowsView: View {
  let rowID: SidebarItemID
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  let selectedWorktreeIDs: Set<Worktree.ID>
  let isRepositoryRemoving: Bool
  let shortcutHint: String?
  var highlightSubtitle: SidebarHighlightRepoTag?
  var leadingInset: CGFloat = 0

  var body: some View {
    let entries = terminalEntries
    if entries.isEmpty {
      SidebarItemRow(
        rowID: rowID,
        store: store,
        terminalsStore: terminalsStore,
        terminalManager: terminalManager,
        selectedWorktreeIDs: selectedWorktreeIDs,
        isRepositoryRemoving: isRepositoryRemoving,
        hideSubtitle: false,
        moveMode: .alwaysDisabled,
        shortcutHint: shortcutHint,
        highlightSubtitle: highlightSubtitle
      )
    } else if let itemStore = store.scope(state: \.sidebarItems[id: rowID], action: \.sidebarItems[id: rowID]) {
      let focusedSurfaceID = focusedSurfaceID
      let groups = branchGroups(entries)
      let showsBranchHeaders = groups.count > 1
      ForEach(groups) { group in
        // When terminals span more than one branch, label each branch group so
        // the dev sees which agents/panes share a branch. A single-branch
        // workspace stays header-free (the branch is already in each subtitle).
        if showsBranchHeaders {
          SidebarBranchHeaderView(branch: group.branch, leadingInset: leadingInset)
        }
        ForEach(group.entries) { entry in
          SidebarTerminalSessionRow(
            worktreeID: rowID,
            tabState: entry.tabState,
            terminalIndex: entry.index,
            itemStore: itemStore,
            parentStore: store,
            terminalManager: terminalManager,
            surfaceID: entry.surfaceID,
            paneIndex: entry.paneIndex,
            paneCount: entry.paneCount,
            highlightSubtitle: highlightSubtitle,
            selectedWorktreeIDs: selectedWorktreeIDs,
            focusedSurfaceID: focusedSurfaceID,
            leadingInset: showsBranchHeaders ? leadingInset + SidebarNestLayout.indentStep : leadingInset
          )
        }
      }
    }
  }

  /// Group the terminal entries by their git branch, preserving first-seen
  /// order. Entries with no resolved branch fall into a trailing `nil` group.
  private func branchGroups(_ entries: [SidebarTerminalSessionEntry]) -> [SidebarBranchGroup] {
    var order: [String] = []
    var byBranch: [String: [SidebarTerminalSessionEntry]] = [:]
    let noBranchKey = "\u{0}none"
    for entry in entries {
      let branch = entry.surfaceID.flatMap { entry.tabState.surfaceGitBranches[$0] }
      let key = branch ?? noBranchKey
      if byBranch[key] == nil { order.append(key) }
      byBranch[key, default: []].append(entry)
    }
    return order.map { key in
      SidebarBranchGroup(id: key, branch: key == noBranchKey ? nil : key, entries: byBranch[key] ?? [])
    }
  }

  /// The single app-wide focused terminal's surface, resolved once here so at
  /// most ONE row can render selected — even if two tabs momentarily both carry
  /// `isSelected` in a stale projection (which showed up as a double-highlight).
  private var focusedSurfaceID: UUID? {
    FocusedTerminal.resolve(
      selectedWorktreeID: store.selectedWorktreeID,
      terminalTabs: terminalsStore.terminalTabs
    )?.surfaceID
  }

  private var terminalEntries: [SidebarTerminalSessionEntry] {
    let tabStates = terminalsStore.terminalTabs.filter { $0.worktreeID == rowID }
    var entries: [SidebarTerminalSessionEntry] = []
    for tabState in tabStates {
      if tabState.surfaceIDs.count > 1 {
        for (offset, surfaceID) in tabState.surfaceIDs.enumerated() {
          entries.append(
            SidebarTerminalSessionEntry(
              index: entries.count + 1,
              tabState: tabState,
              surfaceID: surfaceID,
              paneIndex: offset + 1,
              paneCount: tabState.surfaceIDs.count
            )
          )
        }
      } else {
        entries.append(
          SidebarTerminalSessionEntry(
            index: entries.count + 1,
            tabState: tabState,
            surfaceID: tabState.surfaceIDs.first,
            paneIndex: nil,
            paneCount: tabState.surfaceIDs.count
          )
        )
      }
    }
    return entries
  }
}

private struct SidebarTerminalSessionEntry: Identifiable {
  let index: Int
  let tabState: TerminalTabFeature.State
  let surfaceID: UUID?
  let paneIndex: Int?
  let paneCount: Int

  var id: String {
    "\(tabState.id.rawValue)-\(surfaceID?.uuidString ?? "tab")"
  }
}

/// A run of terminals that share one git branch. `branch == nil` collects
/// terminals whose branch hasn't resolved (or that aren't in a repo).
private struct SidebarBranchGroup: Identifiable {
  let id: String
  let branch: String?
  let entries: [SidebarTerminalSessionEntry]
}

/// Sub-header shown above a branch group when a workspace's terminals span more
/// than one branch, so it's obvious which terminals/agents share a branch.
private struct SidebarBranchHeaderView: View {
  let branch: String?
  let leadingInset: CGFloat

  var body: some View {
    Label {
      Text(branch ?? "No branch")
        .font(AppTypography.caption2.weight(.semibold))
        .monospaced()
        .foregroundStyle(.secondary)
        .lineLimit(1)
    } icon: {
      Image(systemName: "arrow.triangle.branch")
        .font(AppTypography.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    }
    .labelStyle(.verticallyCentered)
    .listRowInsets(.leading, leadingInset)
    .listRowInsets(.trailing, 4)
    .listRowInsets(.vertical, 3)
    .typeSelectEquivalent("")
    .moveDisabled(true)
    .accessibilityLabel("Branch \(branch ?? "none")")
  }
}

private struct SidebarTerminalSessionRow: View {
  let worktreeID: Worktree.ID
  let tabState: TerminalTabFeature.State
  let terminalIndex: Int
  let itemStore: StoreOf<SidebarItemFeature>
  @Bindable var parentStore: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  let surfaceID: UUID?
  let paneIndex: Int?
  let paneCount: Int
  let highlightSubtitle: SidebarHighlightRepoTag?
  let selectedWorktreeIDs: Set<Worktree.ID>
  /// The single app-wide focused terminal's surface, resolved once by the
  /// parent so exactly one row highlights (see `SidebarTerminalSessionRowsView`).
  let focusedSurfaceID: UUID?
  let leadingInset: CGFloat
  @State private var isRenaming = false
  @State private var draftTitle = ""
  @FocusState private var renameFieldFocused: Bool

  /// The first-class terminal for this row, assembled once from its workspace
  /// (tab) state. `nil` only for the degenerate no-surface entry, where the row
  /// falls back to tab-level values. All per-terminal derivation (title, status,
  /// tint, agents) lives on `Terminal`, not in this view.
  private var terminal: Terminal? {
    guard let surfaceID else { return nil }
    return Terminal.resolve(
      id: TerminalID(rawValue: surfaceID),
      tab: tabState,
      paneIndex: paneIndex,
      paneCount: paneCount,
      aliasCandidates: [
        itemStore.name,
        itemStore.resolvedSidebarTitle,
        itemStore.branchName,
        itemStore.workingDirectory.lastPathComponent,
      ]
    )
  }

  private var customTitle: String? { terminal?.customTitle }

  private var tintColor: RepositoryColor? { terminal?.tintColor }

  private var agents: [AgentPresenceFeature.AgentInstance] {
    terminal?.agents ?? tabState.agents
  }

  private var isActive: Bool {
    guard tabState.isSelected else { return false }
    guard let surfaceID else { return true }
    return tabState.activeSurfaceID == surfaceID
  }

  /// The one terminal the app is actually focused on. Compares against the
  /// single `focusedSurfaceID` the parent resolved, so at most ONE row can be
  /// selected app-wide — no double-highlight even if two tabs momentarily both
  /// report `isSelected`.
  private var isSelected: Bool {
    guard let surfaceID else { return false }
    return surfaceID == focusedSurfaceID
  }

  private var status: TerminalStatus {
    terminal?.status
      ?? TerminalStatus(
        agents: tabState.agents, progressDisplay: tabState.progressDisplay, exitCode: nil)
  }

  private var title: String {
    if let terminal { return terminal.displayTitle }
    return tabState.agents.isEmpty
      ? "Shell" : tabState.agents.map(\.agent.displayName).joined(separator: " + ")
  }

  private var subtitle: String {
    var parts: [String] = []
    // Prefer the terminal's OWN branch (from its cwd); fall back to the
    // worktree's branch until the pane reports one.
    if let branch = terminal?.gitBranch {
      parts.append(branch)
    } else if itemStore.kind == .gitWorktree {
      parts.append(itemStore.branchName)
    }
    if let paneIndex, paneCount > 1 {
      parts.append("Pane \(paneIndex)")
    }
    return parts.joined(separator: " · ")
  }

  private var titleStyle: AnyShapeStyle {
    if isSelected { return AnyShapeStyle(Color.white) }
    if let tintColor { return AnyShapeStyle(tintColor.color) }
    if isActive { return AnyShapeStyle(.primary) }
    return AnyShapeStyle(.secondary)
  }

  private var subtitleStyle: AnyShapeStyle {
    isSelected ? AnyShapeStyle(Color.white.opacity(0.75)) : AnyShapeStyle(.secondary)
  }

  private func setCustomTitle(_ title: String?) {
    guard let surfaceID else { return }
    terminalManager.stateIfExists(for: worktreeID)?.setSurfaceCustomTitle(title, for: surfaceID)
  }

  private func setTintColor(_ color: RepositoryColor?) {
    guard let surfaceID else { return }
    terminalManager.stateIfExists(for: worktreeID)?.setSurfaceTintColor(color, for: surfaceID)
  }

  var body: some View {
    rowContent
      .labelStyle(.verticallyCentered)
      .listRowInsets(.leading, leadingInset)
      .listRowInsets(.trailing, 4)
      .listRowInsets(.vertical, 2)
      .typeSelectEquivalent("")
      .moveDisabled(true)
      .contextMenu {
        if surfaceID != nil {
          Button("Rename Pane…") { startRenaming() }
          Menu("Pane Color") {
            Button("Default") { setTintColor(nil) }
            Divider()
            ForEach(RepositoryColor.predefined, id: \.self) { color in
              Button {
                setTintColor(color)
              } label: {
                if tintColor == color {
                  Label(color.displayName, systemImage: "checkmark")
                } else {
                  Text(color.displayName)
                }
              }
            }
          }
          Divider()
        }
        if let worktree = parentStore.state.worktree(for: worktreeID), itemStore.lifecycle == .idle {
          SidebarItemContextMenu(
            worktree: worktree,
            rowID: worktreeID,
            rowKind: itemStore.kind,
            repositoryID: itemStore.repositoryID,
            store: parentStore,
            selectedWorktreeIDs: selectedWorktreeIDs
          )
        }
      }
      .contentShape(.interaction, .rect)
      .accessibilityLabel("\(title), \(subtitle)")
  }

  /// Single click selects, double click renames in place. Plain tap gestures
  /// instead of a Button: inside the sidebar `List`, `TapGesture(count: 2)`
  /// attached to a Button never fires (the row machinery eats it), while
  /// `onTapGesture` on the content does — same pattern as `SidebarItemView`.
  @ViewBuilder private var rowContent: some View {
    if isRenaming {
      sessionLabel(renaming: true)
    } else {
      sessionLabel(renaming: false)
        .contentShape(.rect)
        .onTapGesture(count: 2) {
          guard surfaceID != nil else { return }
          startRenaming()
        }
        .onTapGesture { selectSession() }
        .accessibilityAddTraits(.isButton)
    }
  }

  private func selectSession() {
    parentStore.send(.selectWorktree(worktreeID, focusTerminal: true))
    parentStore.send(.delegate(.selectTerminalTab(worktreeID, tabId: tabState.id)))
    if let surfaceID {
      _ = terminalManager.stateIfExists(for: worktreeID)?.focusSurface(id: surfaceID)
    }
  }

  private func sessionLabel(renaming: Bool) -> some View {
    Label {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          if renaming {
            TextField("Name", text: $draftTitle)
              .textFieldStyle(.plain)
              .font(AppTypography.body)
              .focused($renameFieldFocused)
              .onSubmit { commitRename() }
              .onExitCommand { isRenaming = false }
              .onAppear { renameFieldFocused = true }
              .onChange(of: renameFieldFocused) { _, focused in
                if !focused { commitRename() }
              }
              .accessibilityLabel("Rename pane")
          } else {
            Text(title)
              .font(AppTypography.body.weight(isSelected ? .semibold : .regular))
              .foregroundStyle(titleStyle)
              .lineLimit(1)
              .shimmer(isActive: status.isAnimated && !isSelected)
          }
          Text(subtitle)
            .font(AppTypography.caption)
            .foregroundStyle(renaming ? AnyShapeStyle(.secondary) : subtitleStyle)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        SidebarTerminalSessionTrailingView(
          tabState: tabState,
          agents: agents,
          status: status,
          isSelected: isSelected && !renaming
        )
      }
    } icon: {
      SidebarTerminalSessionIcon(
        agents: agents,
        isActive: isActive,
        isSelected: isSelected && !renaming,
        tintColor: tintColor,
        status: status,
        hasDetectedAgent: terminal?.detectedAgentName != nil
      )
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .background {
      if isSelected, !renaming {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color(nsColor: .selectedContentBackgroundColor))
      }
    }
    .animation(.smooth(duration: 0.18), value: isSelected)
  }

  private func startRenaming() {
    draftTitle = customTitle ?? title
    isRenaming = true
  }

  /// `onSubmit` and the focus-loss `onChange` can both fire for one commit;
  /// the `isRenaming` guard makes the second call a no-op. An emptied field
  /// clears the custom name (back to the automatic one).
  private func commitRename() {
    guard isRenaming else { return }
    isRenaming = false
    let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      setCustomTitle(nil)
      return
    }
    guard trimmed != title else { return }
    setCustomTitle(trimmed)
  }
}

/// Sidebar presentation for the shared `TerminalStatus`. The classification
/// (and `isAnimated` / `accessibilityLabel`) lives on the model; color and pulse
/// timing are view concerns and stay here.
private extension TerminalStatus {
  var color: Color {
    switch self {
    case .needsAttention: .orange
    case .running: .blue
    case .completed: .green
    case .failed: .red
    case .idle: .secondary.opacity(0.55)
    }
  }

  var pulseDuration: Double {
    switch self {
    case .needsAttention: 0.8
    case .running: 1.15
    case .completed, .failed, .idle: 0
    }
  }
}

private struct SidebarTerminalSessionIcon: View {
  let agents: [AgentPresenceFeature.AgentInstance]
  let isActive: Bool
  let isSelected: Bool
  let tintColor: RepositoryColor?
  let status: TerminalStatus
  /// A hook-free agent was detected from the terminal title (no presence badge);
  /// show an agent glyph instead of the plain terminal one.
  var hasDetectedAgent: Bool = false

  private var glyphStyle: AnyShapeStyle {
    if isSelected { return AnyShapeStyle(Color.white) }
    if let tintColor { return AnyShapeStyle(tintColor.color) }
    if isActive { return AnyShapeStyle(status.color) }
    return AnyShapeStyle(.secondary)
  }

  var body: some View {
    Group {
      if let first = agents.first {
        AgentBadgeView(agent: first.agent, size: AppChromeMetrics.Sidebar.rowIconSize, awaitingInput: first.awaitingInput)
      } else {
        Image(systemName: hasDetectedAgent ? "sparkles" : "terminal")
          .font(AppTypography.caption.weight(.semibold))
          .foregroundStyle(glyphStyle)
      }
    }
    .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    .accessibilityHidden(true)
  }
}

private struct SidebarTerminalSessionTrailingView: View {
  let tabState: TerminalTabFeature.State
  let agents: [AgentPresenceFeature.AgentInstance]
  let status: TerminalStatus
  var isSelected = false

  var body: some View {
    HStack(spacing: AppChromeMetrics.Sidebar.accessorySpacing) {
      if agents.count > 1 {
        AgentAvatarGroupView(instances: agents, size: AppChromeMetrics.Sidebar.rowIconSize)
      }
      SidebarTerminalStatusDot(status: status)
        .padding(1.5)
        .background {
          // Keeps a blue "running" dot visible on the accent selection fill.
          if isSelected {
            Circle().fill(Color.white.opacity(0.9))
          }
        }
      if tabState.hasUnseenNotifications {
        Text("\(tabState.unseenNotificationCount)")
          .font(AppTypography.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.orange)
          .accessibilityLabel("\(tabState.unseenNotificationCount) unread notifications")
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}

private struct SidebarTerminalStatusDot: View {
  let status: TerminalStatus
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if status.isAnimated, !reduceMotion {
      PulseDot(status: status)
    } else {
      StaticDot(status: status)
    }
  }
}

private struct StaticDot: View {
  let status: TerminalStatus

  var body: some View {
    Circle()
      .fill(status.color)
      .frame(width: AppChromeMetrics.Sidebar.statusDotSize, height: AppChromeMetrics.Sidebar.statusDotSize)
      .accessibilityLabel(status.accessibilityLabel)
  }
}

private struct PulseDot: View {
  let status: TerminalStatus

  var body: some View {
    Circle()
      .fill(status.color)
      .frame(width: AppChromeMetrics.Sidebar.statusDotSize, height: AppChromeMetrics.Sidebar.statusDotSize)
      .phaseAnimator([false, true]) { content, pulse in
        content
          .scaleEffect(pulse ? 1.22 : 0.9)
          .shadow(color: status.color.opacity(pulse ? 0.55 : 0), radius: pulse ? 4 : 0)
          .opacity(pulse ? 1 : 0.72)
      } animation: { _ in
        .easeInOut(duration: status.pulseDuration)
      }
      .accessibilityLabel(status.accessibilityLabel)
  }
}

private struct SidebarRecentProjectRow: View {
  let repository: Repository
  let rowIDs: [SidebarItemID]
  let customTitle: String?
  let color: RepositoryColor?
  @Bindable var store: StoreOf<RepositoriesFeature>

  @State private var isRenaming = false
  @State private var draftTitle = ""
  @FocusState private var renameFieldFocused: Bool

  private var displayName: String {
    Repository.sidebarDisplayName(custom: customTitle, fallback: repository.name)
  }

  private var subtitle: String? {
    repository.host?.displayAuthority
  }

  private var projects: [SidebarProject] {
    Array(store.state.sidebar.projects.values)
  }

  private var currentProjectID: ProjectID? {
    store.state.sidebar.projectID(containing: repository.id)
  }

  var body: some View {
    rowContent
      .labelStyle(.verticallyCentered)
      .listRowInsets(.leading, 0)
      .listRowInsets(.trailing, 4)
      .listRowInsets(.vertical, 6)
      .typeSelectEquivalent("")
      .moveDisabled(true)
      .contextMenu {
        Button("New Project with This…") {
          store.send(.createProject(name: "New Project", repositoryIDs: [repository.id]))
        }
        if !projects.isEmpty {
          Menu("Add to Project") {
            ForEach(projects) { project in
              Button {
                store.send(.addRepositoryToProject(repository.id, project.id))
              } label: {
                if project.id == currentProjectID {
                  Label(project.name, systemImage: "checkmark")
                } else {
                  Text(project.name)
                }
              }
            }
          }
        }
        if currentProjectID != nil {
          Button("Remove from Project") {
            store.send(.removeRepositoryFromProject(repository.id))
          }
        }
      }
      .accessibilityLabel(displayName)
  }

  /// Single click selects; double click renames the workspace in place, same
  /// interaction contract as terminal rows and tab-bar tabs. Tap gestures on
  /// the content (not a Button) — see `SidebarTerminalSessionRow.rowContent`.
  @ViewBuilder private var rowContent: some View {
    if isRenaming {
      projectLabel(renaming: true)
    } else {
      projectLabel(renaming: false)
        .contentShape(.rect)
        .onTapGesture(count: 2) { startRenaming() }
        .onTapGesture {
          if let rowID = rowIDs.first {
            store.send(.selectWorktree(rowID, focusTerminal: true))
          }
        }
        .accessibilityAddTraits(.isButton)
    }
  }

  private func projectLabel(renaming: Bool) -> some View {
    Label {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          if renaming {
            TextField("Name", text: $draftTitle)
              .textFieldStyle(.plain)
              .font(AppTypography.body)
              .focused($renameFieldFocused)
              .onSubmit { commitRename() }
              .onExitCommand { isRenaming = false }
              .onAppear { renameFieldFocused = true }
              .onChange(of: renameFieldFocused) { _, focused in
                if !focused { commitRename() }
              }
              .accessibilityLabel("Rename workspace")
          } else {
            Text(displayName)
              .font(AppTypography.body)
              .foregroundStyle(color?.color ?? .primary)
              .lineLimit(1)
          }
          if let subtitle {
            Text(subtitle)
              .font(AppTypography.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        if rowIDs.count > 1 {
          Text("\(rowIDs.count)")
            .font(AppTypography.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
    } icon: {
      Image(systemName: repository.host == nil ? "folder" : "wifi")
        .font(AppTypography.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    }
  }

  private func startRenaming() {
    draftTitle = displayName
    isRenaming = true
  }

  /// `onSubmit` and the focus-loss `onChange` can both fire for one commit;
  /// the `isRenaming` guard makes the second call a no-op. An emptied field
  /// resets to the folder-derived name.
  private func commitRename() {
    guard isRenaming else { return }
    isRenaming = false
    let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed != displayName else { return }
    if repository.isGitRepository {
      store.send(.commitRepositorySectionTitle(repository.id, title: trimmed))
    } else if let rowID = rowIDs.first {
      store.send(.commitInlineTitle(worktreeID: rowID, repositoryID: repository.id, title: trimmed))
    }
  }
}

/// Collapsible header for a user-created Project grouping several repositories.
/// Single click toggles collapse; double click renames inline. Context menu
/// renames or deletes (delete ungroups its repos, never deletes them).
private struct SidebarProjectHeaderView: View {
  let projectID: ProjectID
  let name: String
  let color: RepositoryColor?
  let collapsed: Bool
  let memberCount: Int
  @Bindable var store: StoreOf<RepositoriesFeature>

  @State private var isRenaming = false
  @State private var draftTitle = ""
  @FocusState private var renameFieldFocused: Bool

  var body: some View {
    rowContent
      .labelStyle(.verticallyCentered)
      .listRowInsets(.leading, 0)
      .listRowInsets(.trailing, 4)
      .listRowInsets(.vertical, 6)
      .typeSelectEquivalent("")
      .moveDisabled(true)
      .contextMenu {
        Button("Rename Project…") { startRenaming() }
        Menu("Project Color") {
          Button("Default") { store.send(.setProjectColor(projectID, nil)) }
          Divider()
          ForEach(RepositoryColor.predefined, id: \.self) { swatch in
            Button {
              store.send(.setProjectColor(projectID, swatch))
            } label: {
              if swatch == color {
                Label(swatch.displayName, systemImage: "checkmark")
              } else {
                Text(swatch.displayName)
              }
            }
          }
        }
        Divider()
        Button("Delete Project", role: .destructive) {
          store.send(.deleteProject(projectID))
        }
      }
      .accessibilityLabel("Project \(name), \(memberCount) repositories")
  }

  @ViewBuilder private var rowContent: some View {
    if isRenaming {
      projectLabel(renaming: true)
    } else {
      projectLabel(renaming: false)
        .contentShape(.rect)
        .onTapGesture(count: 2) { startRenaming() }
        .onTapGesture { store.send(.toggleProjectCollapsed(projectID)) }
        .accessibilityAddTraits(.isButton)
    }
  }

  private func projectLabel(renaming: Bool) -> some View {
    Label {
      HStack(spacing: 8) {
        if renaming {
          TextField("Name", text: $draftTitle)
            .textFieldStyle(.plain)
            .font(AppTypography.caption.weight(.semibold))
            .focused($renameFieldFocused)
            .onSubmit { commitRename() }
            .onExitCommand { isRenaming = false }
            .onAppear { renameFieldFocused = true }
            .onChange(of: renameFieldFocused) { _, focused in
              if !focused { commitRename() }
            }
            .accessibilityLabel("Rename project")
        } else {
          Text(name.uppercased())
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(color?.color ?? .secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        Text("\(memberCount)")
          .font(AppTypography.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: collapsed ? "chevron.right" : "chevron.down")
        .font(AppTypography.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    }
  }

  private func startRenaming() {
    draftTitle = name
    isRenaming = true
  }

  private func commitRename() {
    guard isRenaming else { return }
    isRenaming = false
    let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != name else { return }
    store.send(.renameProject(projectID, title: trimmed))
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
        shortcutHintByID: shortcutHintByID
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
    case .folder(let repositoryID, let rowID):
      if let repository = store.state.repositories[id: repositoryID] {
        if showsRecentsHeader {
          Section {
            SidebarRecentProjectRow(
              repository: repository,
              rowIDs: [rowID],
              customTitle: store.state.sidebar.sections[repositoryID]?.title,
              color: store.state.sidebar.sections[repositoryID]?.color,
              store: store,
            )
          } header: {
            SidebarSessionsHeaderView(title: "Recents")
          }
        } else {
          SidebarRecentProjectRow(
            repository: repository,
            rowIDs: [rowID],
            customTitle: store.state.sidebar.sections[repositoryID]?.title,
            color: store.state.sidebar.sections[repositoryID]?.color,
            store: store,
          )
        }
      }
    case .repository(let repositoryID, let groups):
      if let repository = store.state.repositories[id: repositoryID] {
        SidebarRepositorySessionsSection(
          repository: repository,
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
}

private struct SidebarRepositorySessionsSection: View {
  let repository: Repository
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
    let section = store.state.sidebar.sections[repository.id]
    SidebarRecentProjectRow(
      repository: repository,
      rowIDs: groups.flatMap(\.rowIDs),
      customTitle: section?.title,
      color: section?.color,
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
            ? "Stop tracking this SSH folder in p/term. Remote files are untouched."
            : "Stop tracking this project in p/term. Files on disk are untouched."
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
