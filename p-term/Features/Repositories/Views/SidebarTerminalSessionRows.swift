import AppKit
import ComposableArchitecture
import OrderedCollections
import PTermSettingsShared
import Sharing
import SwiftUI
import UniformTypeIdentifiers

// Terminal-session rows: every terminal is always a *child* of its workspace.
//
// MUST hierarchy (never flatten):
//   [project header]            ← list body, when multi-project / multi-worktree
//     [workspace parent]        ← this view
//       [active terminal…]      ← always visible children
//       | [New Terminal CTA]    ← when no active terminals
//
// No branch names in this list — git branch lives in toolbar/status chrome.
// Titles never carry color — only indicators do. Git +/- lives on the workspace.
//
// Interaction contract:
// - Drag unit = WORKSPACE (worktree ID), never a terminal pane.
// - Children ALWAYS render (collapse is intentionally not used for hiding —
//   nesting is a product requirement; hiding children breaks the hierarchy).
// - Terminal rows do not initiate pin-drag (they only select/focus).
struct SidebarTerminalSessionRowsView: View {
  let rowID: SidebarItemID
  @Bindable var store: StoreOf<RepositoriesFeature>
  @Bindable var terminalsStore: StoreOf<TerminalsFeature>
  let terminalManager: WorktreeTerminalManager
  let selectedWorktreeIDs: Set<Worktree.ID>
  let isRepositoryRemoving: Bool
  let shortcutHint: String?
  var highlightSubtitle: SidebarHighlightRepoTag?
  /// The app-wide focused terminal, resolved ONCE in `SidebarListView.body` and
  /// threaded down — never re-derived per row.
  var focusedTabID: TerminalTabID?
  var focusedSurfaceID: UUID?
  var leadingInset: CGFloat = 0
  /// Pinned section: same full hierarchy (workspace + children always on).
  var emphasizePin: Bool = false

  private var terminalInset: CGFloat {
    SidebarNestLayout.terminalUnderWorkspace(workspaceLeading: leadingInset)
  }

  /// Nested under a project header when the parent already indented this unit.
  private var isNestedUnderProject: Bool { leadingInset > 0 }

  var body: some View {
    // Group forces SwiftUI List to expand parent + children as sibling rows.
    // Without Group, some macOS List configurations only keep the first child.
    Group {
      workspaceParent
      workspaceChildren
    }
  }

  @ViewBuilder
  private var workspaceParent: some View {
    let entries = terminalEntries
    let isWorkspaceSelected = selectedWorktreeIDs.contains(rowID)
    if let itemStore = store.scope(state: \.sidebarItems[id: rowID], action: \.sidebarItems[id: rowID]) {
      let repositoryName =
        highlightSubtitle?.repoName
        ?? store.state.repositoryName(for: itemStore.repositoryID)
      SidebarWorkspaceParentRow(
        itemStore: itemStore,
        parentStore: store,
        selectedWorktreeIDs: selectedWorktreeIDs,
        isSelected: isWorkspaceSelected,
        leadingInset: leadingInset,
        shortcutHint: shortcutHint,
        openTerminalCount: entries.count,
        isCollapsed: false,
        repositoryName: repositoryName,
        isNestedUnderProject: isNestedUnderProject,
        // Nesting is mandatory — no collapse control that hides children.
        onToggleCollapse: nil,
        terminalManager: terminalManager
      )
    } else if entries.isEmpty {
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
    }
  }

  @ViewBuilder
  private var workspaceChildren: some View {
    // MUST: always render children under an existing workspace row.
    // Active terminals when present; New Terminal CTA when empty.
    if store.state.sidebarItems[id: rowID] != nil {
      let entries = terminalEntries
      let isWorkspaceSelected = selectedWorktreeIDs.contains(rowID)
      if entries.isEmpty {
        SidebarNewTerminalCTARow(
          worktreeID: rowID,
          parentStore: store,
          terminalManager: terminalManager,
          leadingInset: terminalInset,
          isWorkspaceActive: isWorkspaceSelected
        )
      } else if let itemStore = store.scope(
        state: \.sidebarItems[id: rowID], action: \.sidebarItems[id: rowID]
      ) {
        ForEach(entries) { entry in
          SidebarTerminalSessionRow(
            worktreeID: rowID,
            tabState: entry.tabState,
            itemStore: itemStore,
            parentStore: store,
            terminalManager: terminalManager,
            surfaceID: entry.surfaceID,
            paneIndex: entry.paneIndex,
            paneCount: entry.paneCount,
            selectedWorktreeIDs: selectedWorktreeIDs,
            focusedTabID: focusedTabID,
            focusedSurfaceID: focusedSurfaceID,
            leadingInset: terminalInset
          )
        }
      }
    }
  }

  private var terminalEntries: [SidebarTerminalSessionEntry] {
    let tabStates = terminalsStore.terminalTabs.filter {
      $0.worktreeID == rowID && !$0.surfaceIDs.isEmpty
    }
    var entries: [SidebarTerminalSessionEntry] = []
    for tabState in tabStates {
      if tabState.surfaceIDs.count > 1 {
        for (offset, surfaceID) in tabState.surfaceIDs.enumerated() {
          entries.append(
            SidebarTerminalSessionEntry(
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

// MARK: - Workspace title (never a git branch)

/// Pure title cascade for the sidebar workspace row.
/// Branch names belong in toolbar/status chrome — not in this list.
enum SidebarWorkspaceTitle {
  /// Input fields for `resolve` — packed so call sites stay named without
  /// tripping the 5-parameter SwiftLint limit.
  struct Inputs: Sendable, Equatable {
    var customTitle: String?
    var repositoryName: String?
    var isFolder: Bool
    var folderOrName: String
    var workingDirectoryName: String
    var isNestedUnderProject: Bool
  }

  static func resolve(_ inputs: Inputs) -> String {
    let custom = inputs.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let custom, !custom.isEmpty { return custom }

    let repo = inputs.repositoryName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let dir = inputs.workingDirectoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    let folder = inputs.folderOrName.trimmingCharacters(in: .whitespacesAndNewlines)
    // Never use slashy branch paths (`feat/foo`) as a title.
    let cleanFolder = folder.contains("/") ? "" : folder

    // Nested under a multi-worktree project header: disambiguate by folder/dir.
    // Never invent a useless "Workspace" label — that adds a redundant level.
    if inputs.isNestedUnderProject {
      if !dir.isEmpty, dir != repo { return dir }
      if !cleanFolder.isEmpty, cleanFolder != repo { return cleanFolder }
      // Last resort under a project: still a real name, not the product noun.
      if !dir.isEmpty { return dir }
      if let repo, !repo.isEmpty { return repo }
      return cleanFolder.isEmpty ? "Untitled" : cleanFolder
    }

    // Flat (single worktree): the row IS the project — use the repo name.
    if let repo, !repo.isEmpty { return repo }
    if inputs.isFolder, !cleanFolder.isEmpty { return cleanFolder }
    if !dir.isEmpty { return dir }
    if !cleanFolder.isEmpty { return cleanFolder }
    return "Untitled"
  }
}

// MARK: - Workspace parent (identity + git)

/// The workspace row that owns nested terminals.
/// Active (selected) title = primary/white; inactive = secondary/gray.
/// Color only on git +/-. No row pin glyph (pin is on the Pinned list title).
/// Pin/unpin via drag between lists or context menu.
/// Title is product identity (repo / custom / folder) — never a git branch.
///
/// Click targets are split deliberately so first-click is instant:
/// - chevron → collapse
/// - rest of row → select + focus
private struct SidebarWorkspaceParentRow: View {
  let itemStore: StoreOf<SidebarItemFeature>
  @Bindable var parentStore: StoreOf<RepositoriesFeature>
  let selectedWorktreeIDs: Set<Worktree.ID>
  let isSelected: Bool
  let leadingInset: CGFloat
  let shortcutHint: String?
  let openTerminalCount: Int
  let isCollapsed: Bool
  let repositoryName: String?
  let isNestedUnderProject: Bool
  /// `nil` when there are no children to collapse.
  let onToggleCollapse: (() -> Void)?
  let terminalManager: WorktreeTerminalManager

  private var isPinned: Bool { itemStore.isPinned }

  private var title: String {
    SidebarWorkspaceTitle.resolve(
      .init(
        customTitle: itemStore.customTitle,
        repositoryName: repositoryName,
        isFolder: itemStore.isFolder,
        folderOrName: itemStore.name,
        workingDirectoryName: itemStore.workingDirectory.lastPathComponent,
        isNestedUnderProject: isNestedUnderProject
      )
    )
  }

  private var addedLines: Int { itemStore.addedLines ?? 0 }
  private var removedLines: Int { itemStore.removedLines ?? 0 }
  private var hasDiffStats: Bool { addedLines + removedLines > 0 }

  /// Busy agent/script → solid status mark; otherwise quiet hollow (Claude dots).
  private var hasActivity: Bool {
    itemStore.hasAgentActivity || itemStore.isProgressBusy || itemStore.hasUnseenNotifications
      || !itemStore.runningScripts.isEmpty
  }

  var body: some View {
    // No selection wash — active state is title color only.
    HStack(spacing: SidebarNestLayout.rowSpacing) {
      if let onToggleCollapse {
        Button(action: onToggleCollapse) {
          Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
            .font(AppTypography.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(
              width: SidebarNestLayout.chevronSlot,
              height: SidebarNestLayout.chevronSlot
            )
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SidebarAccessibility.collapseControlLabel(isCollapsed: isCollapsed))
      }

      SidebarWorkspaceLeadingMark(
        isFolder: itemStore.isFolder,
        isRemote: itemStore.isRemote,
        hasActivity: hasActivity,
        isSelected: isSelected
      )

      // Same size as New/Open (body 13). Weight + primary color carry hierarchy;
      // children use callout 12 — one clear step down, no title3 jump.
      Text(title)
        .font(AppTypography.body.weight(isSelected ? .semibold : .medium))
        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.85)))
        .lineLimit(1)
        .layoutPriority(1)

      if hasDiffStats {
        DiffStatsContent(addedLines: addedLines, removedLines: removedLines)
      }

      Spacer(minLength: 4)

      if isCollapsed, openTerminalCount > 0 {
        Text("\(openTerminalCount)")
          .font(AppTypography.caption2)
          .monospacedDigit()
          .foregroundStyle(.tertiary)
      }

      if let shortcutHint {
        Text(shortcutHint)
          .font(AppTypography.caption2)
          .monospacedDigit()
          .foregroundStyle(.tertiary)
      }
    }
    .frame(minHeight: SidebarNestLayout.rowMinHeight, alignment: .center)
    .contentShape(.rect)
    // Re-click re-focuses terminal (List selection alone won't re-fire).
    .simultaneousGesture(
      TapGesture().onEnded {
        parentStore.send(.selectWorktree(itemStore.id, focusTerminal: true))
      }
    )
    // Keep a11y traits adjacent to the gesture: SwiftLint only walks ~20 AST
    // parents looking for `.isButton` / `.isLink`.
    .accessibilityLabel(SidebarAccessibility.workspaceRowLabel(title: title))
    .accessibilityAddTraits(.isButton)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .onDrag {
      SidebarPinDrag.provider(for: itemStore.id)
    } preview: {
      Text(title)
        .font(AppTypography.body.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
    // No List tag / no selection highlight — active = title color only.
    .id(itemStore.id)
    .listRowInsets(.leading, max(0, leadingInset))
    .listRowInsets(.trailing, SidebarNestLayout.trailingInset)
    .listRowInsets(.vertical, SidebarNestLayout.rowVerticalInset)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .selectionDisabled(true)
    .typeSelectEquivalent("")
    .moveDisabled(true)
    .contextMenu {
      if canTogglePin {
        if isPinned {
          Button("Unpin", systemImage: "pin.slash", action: togglePin)
        } else {
          Button("Pin", systemImage: "pin", action: togglePin)
        }
        Divider()
      }
      if let worktree = parentStore.state.worktree(for: itemStore.id), itemStore.lifecycle == .idle {
        SidebarItemContextMenu(
          worktree: worktree,
          rowID: itemStore.id,
          rowKind: itemStore.kind,
          repositoryID: itemStore.repositoryID,
          store: parentStore,
          selectedWorktreeIDs: selectedWorktreeIDs,
          showsDestructive: true
        )
      }
    }
  }

  private var canTogglePin: Bool {
    // Any workspace can be pinned (including git main) except pending creates.
    !itemStore.lifecycle.isPending
  }

  private func togglePin() {
    if itemStore.isPinned {
      parentStore.send(.unpinWorktree(itemStore.id))
    } else {
      parentStore.send(.pinWorktree(itemStore.id))
    }
  }
}

/// Claude-style leading mark: monochrome activity ring / folder / remote.
private struct SidebarWorkspaceLeadingMark: View {
  let isFolder: Bool
  let isRemote: Bool
  let hasActivity: Bool
  let isSelected: Bool

  var body: some View {
    Group {
      if isFolder {
        Image(systemName: isRemote ? "network" : "folder")
          .font(AppTypography.caption.weight(.medium))
          .foregroundStyle(.secondary)
      } else if hasActivity {
        // Solid mark when busy — secondary, not semantic color.
        Circle()
          .fill(Color.secondary.opacity(isSelected ? 0.85 : 0.65))
          .frame(
            width: AppChromeMetrics.Sidebar.statusDotSize,
            height: AppChromeMetrics.Sidebar.statusDotSize
          )
      } else {
        Circle()
          .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
          .frame(
            width: AppChromeMetrics.Sidebar.statusDotSize + 1,
            height: AppChromeMetrics.Sidebar.statusDotSize + 1
          )
      }
    }
    .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    .accessibilityHidden(true)
  }
}

/// Workspace pin drag/drop — same pattern as terminal split drag
/// (`TerminalSplitTreeView`): custom UTType + `registerDataRepresentation` +
/// `DropDelegate`. Plain-text `NSItemProvider` is unreliable inside List.
enum SidebarPinDrag {
  /// Must match `UTExportedTypeDeclarations` in Info.plist.
  static let dragType = UTType(exportedAs: "app.p-term.worktreePin")

  static func provider(for worktreeID: Worktree.ID) -> NSItemProvider {
    let provider = NSItemProvider()
    let data = Data(worktreeID.rawValue.utf8)
    provider.registerDataRepresentation(
      forTypeIdentifier: dragType.identifier,
      visibility: .all
    ) { completion in
      completion(data, nil)
      return nil
    }
    return provider
  }

  static func loadID(from info: DropInfo, completion: @escaping @MainActor (Worktree.ID?) -> Void) {
    let providers = info.itemProviders(for: [dragType])
    guard let provider = providers.first else {
      Task { @MainActor in completion(nil) }
      return
    }
    provider.loadDataRepresentation(forTypeIdentifier: dragType.identifier) { data, _ in
      let id = data
        .flatMap { String(data: $0, encoding: .utf8) }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .flatMap { $0.isEmpty ? nil : WorktreeID($0) }
      Task { @MainActor in completion(id) }
    }
  }
}

/// Drop onto the Pinned zone (or Active/Workspaces for unpin).
struct SidebarPinDropDelegate: DropDelegate {
  @Binding var isTargeted: Bool
  let onDropID: (Worktree.ID) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    info.hasItemsConforming(to: [SidebarPinDrag.dragType])
  }

  func dropEntered(info: DropInfo) {
    isTargeted = true
  }

  func dropExited(info: DropInfo) {
    isTargeted = false
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard info.hasItemsConforming(to: [SidebarPinDrag.dragType]) else {
      return DropProposal(operation: .forbidden)
    }
    isTargeted = true
    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    isTargeted = false
    guard info.hasItemsConforming(to: [SidebarPinDrag.dragType]) else { return false }
    SidebarPinDrag.loadID(from: info) { id in
      guard let id else { return }
      onDropID(id)
    }
    return true
  }
}

// MARK: - Terminal children

private struct SidebarTerminalSessionEntry: Identifiable {
  let tabState: TerminalTabFeature.State
  let surfaceID: UUID?
  let paneIndex: Int?
  let paneCount: Int

  var id: String {
    "\(tabState.id.rawValue)-\(surfaceID?.uuidString ?? "tab")"
  }
}

/// Nested CTA when a workspace has no active terminals — monochrome child row
/// under the workspace, same rhythm as Shell rows (never a banner).
private struct SidebarNewTerminalCTARow: View {
  let worktreeID: Worktree.ID
  @Bindable var parentStore: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  let leadingInset: CGFloat
  let isWorkspaceActive: Bool

  var body: some View {
    Button(action: startTerminal) {
      HStack(spacing: SidebarNestLayout.rowSpacing) {
        Image(systemName: "plus")
          .font(AppTypography.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(
            width: AppChromeMetrics.Sidebar.rowIconSize,
            height: AppChromeMetrics.Sidebar.rowIconSize
          )
          .accessibilityHidden(true)

        Text("New Terminal")
          .font(AppTypography.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .frame(minHeight: SidebarNestLayout.rowMinHeight, alignment: .center)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .listRowInsets(.leading, leadingInset)
    .listRowInsets(.trailing, SidebarNestLayout.trailingInset)
    .listRowInsets(.vertical, SidebarNestLayout.rowVerticalInset)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .typeSelectEquivalent("")
    .moveDisabled(true)
    .selectionDisabled(true)
    .help("Start a new terminal in this workspace")
    .accessibilityLabel(SidebarAccessibility.newTerminalCTALabel())
    .accessibilityHint("Starts a shell session in this workspace")
  }

  private func startTerminal() {
    parentStore.send(.selectWorktree(worktreeID, focusTerminal: true))
    guard let worktree = parentStore.state.worktree(for: worktreeID), !worktree.isMissing else {
      return
    }
    let shouldRunSetupScript =
      parentStore.state.sidebarItems[id: worktreeID]?.lifecycle == .pending
    terminalManager.handleCommand(
      .createTab(worktree, runSetupScriptIfNew: shouldRunSetupScript)
    )
  }
}

private struct SidebarTerminalSessionRow: View {
  let worktreeID: Worktree.ID
  let tabState: TerminalTabFeature.State
  let itemStore: StoreOf<SidebarItemFeature>
  @Bindable var parentStore: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  let surfaceID: UUID?
  let paneIndex: Int?
  let paneCount: Int
  let selectedWorktreeIDs: Set<Worktree.ID>
  let focusedTabID: TerminalTabID?
  let focusedSurfaceID: UUID?
  let leadingInset: CGFloat
  @State private var isRenaming = false
  @State private var draftTitle = ""

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

  private var isSelected: Bool {
    if let surfaceID { return surfaceID == focusedSurfaceID }
    return tabState.id == focusedTabID
  }

  private var status: TerminalStatus {
    terminal?.status
      ?? TerminalStatus(
        agents: tabState.agents, progressDisplay: tabState.progressDisplay, exitCode: nil)
  }

  /// Stable terminal label — never the workspace branch, never agent flip-flop.
  /// Identity lives on the parent workspace; this row is the shell session.
  private var title: String {
    if let custom = terminal?.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
      !custom.isEmpty
    {
      return custom
    }
    if let paneIndex, paneCount > 1 {
      return "Pane \(paneIndex)"
    }
    return "Shell"
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
      .listRowInsets(.leading, leadingInset)
      .listRowInsets(.trailing, SidebarNestLayout.trailingInset)
      .listRowInsets(.vertical, SidebarNestLayout.rowVerticalInset)
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .typeSelectEquivalent("")
      .moveDisabled(true)
      .selectionDisabled(true)
      // Terminals are never the pin-drag source. Pin always targets the parent workspace.
      .contextMenu {
        if canTogglePin {
          if itemStore.isPinned {
            Button("Unpin", systemImage: "pin.slash") {
              parentStore.send(.unpinWorktree(worktreeID))
            }
          } else {
            Button("Pin", systemImage: "pin") {
              parentStore.send(.pinWorktree(worktreeID))
            }
          }
          Divider()
        }
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
            selectedWorktreeIDs: selectedWorktreeIDs,
            showsDestructive: false
          )
          Divider()
          Button("Close Terminal", systemImage: "xmark", role: .destructive) {
            closeSession()
          }
        }
      }
      .contentShape(.interaction, .rect)
      .accessibilityLabel(title)
  }

  @ViewBuilder private var rowContent: some View {
    if isRenaming {
      sessionLabel(renaming: true)
    } else {
      // simultaneousGesture (not onTapGesture alone): List NSTableView eats
      // plain taps; this fires on first click without fighting drag.
      sessionLabel(renaming: false)
        .contentShape(.rect)
        .simultaneousGesture(
          TapGesture(count: 2).onEnded {
            guard surfaceID != nil else { return }
            startRenaming()
          }
        )
        .simultaneousGesture(
          TapGesture().onEnded { selectSession() }
        )
        .accessibilityAddTraits(.isButton)
    }
  }

  private var canTogglePin: Bool {
    !itemStore.lifecycle.isPending
  }

  private func selectSession() {
    parentStore.send(.selectWorktree(worktreeID, focusTerminal: true))
    parentStore.send(.delegate(.selectTerminalTab(worktreeID, tabId: tabState.id)))
    if let surfaceID {
      _ = terminalManager.stateIfExists(for: worktreeID)?.focusSurface(id: surfaceID)
    }
  }

  private func closeSession() {
    guard let worktree = parentStore.state.worktree(for: worktreeID) else { return }
    if let surfaceID, paneCount > 1 {
      terminalManager.handleCommand(.destroySurface(worktree, tabID: tabState.id, surfaceID: surfaceID))
    } else {
      terminalManager.handleCommand(.destroyTab(worktree, tabID: tabState.id))
    }
  }

  private func sessionLabel(renaming: Bool) -> some View {
    // Child step: callout 12 under workspace body 13. Secondary unless focused.
    let titleStyle: AnyShapeStyle =
      (isSelected && !renaming) ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    return HStack(spacing: SidebarNestLayout.rowSpacing) {
      SidebarTerminalSessionLeading(
        agents: agents,
        status: status,
        isSelected: isSelected && !renaming,
        hasDetectedAgent: terminal?.detectedTitleAgent != nil,
        detectedAgentLogo: terminal?.detectedTitleAgent?.agent
      )

      if renaming {
        SidebarInlineRenameField(
          text: $draftTitle,
          accessibilityLabel: "Rename pane",
          onCommit: commitRename,
          onCancel: { isRenaming = false }
        )
      } else {
        Text(title)
          .font(AppTypography.callout)
          .foregroundStyle(titleStyle)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      if tabState.hasUnseenNotifications {
        Text("\(tabState.unseenNotificationCount)")
          .font(AppTypography.caption2)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    .frame(minHeight: SidebarNestLayout.rowMinHeight, alignment: .center)
    .contentShape(.rect)
  }

  private func startRenaming() {
    draftTitle = customTitle ?? title
    isRenaming = true
  }

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

// MARK: - Terminal indicators (color OK)

private extension TerminalStatus {
  /// Monochrome — only git +/- on the workspace row is colored.
  var color: Color { .secondary.opacity(0.55) }

  var pulseDuration: Double {
    switch self {
    case .needsAttention: 0.8
    case .running: 1.15
    case .completed, .failed, .idle: 0
    }
  }
}

private struct SidebarTerminalSessionLeading: View {
  let agents: [AgentPresenceFeature.AgentInstance]
  let status: TerminalStatus
  let isSelected: Bool
  var hasDetectedAgent: Bool = false
  var detectedAgentLogo: SkillAgent?

  var body: some View {
    // Monochrome status mark only — git colors stay on the workspace parent.
    Group {
      if !agents.isEmpty || hasDetectedAgent || status != .idle {
        Circle()
          .fill(Color.secondary.opacity(isSelected ? 0.75 : 0.5))
          .frame(
            width: AppChromeMetrics.Sidebar.statusDotSize,
            height: AppChromeMetrics.Sidebar.statusDotSize
          )
      } else {
        Circle()
          .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.5)
          .frame(
            width: AppChromeMetrics.Sidebar.statusDotSize + 1,
            height: AppChromeMetrics.Sidebar.statusDotSize + 1
          )
      }
    }
    .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    .accessibilityHidden(true)
  }
}

private struct SidebarTerminalSessionTrailingView: View {
  let tabState: TerminalTabFeature.State
  let agents: [AgentPresenceFeature.AgentInstance]
  var isSelected = false

  var body: some View {
    HStack(spacing: AppChromeMetrics.Sidebar.accessorySpacing) {
      if agents.count > 1 {
        AgentAvatarGroupView(instances: agents, size: AppChromeMetrics.Sidebar.rowIconSize)
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if reduceMotion {
      StaticDot(status: status)
    } else {
      Circle()
        .fill(status.color)
        .frame(width: AppChromeMetrics.Sidebar.statusDotSize, height: AppChromeMetrics.Sidebar.statusDotSize)
        .phaseAnimator([false, true]) { content, pulse in
          content
            .scaleEffect(pulse ? 1.22 : 0.9)
            .opacity(pulse ? 1 : 0.72)
            .background {
              Circle()
                .fill(status.color)
                .blur(radius: 3)
                .scaleEffect(1.6)
                .opacity(pulse ? 0.55 : 0)
            }
        } animation: { _ in
          .easeInOut(duration: status.pulseDuration)
        }
        .accessibilityLabel(status.accessibilityLabel)
    }
  }
}
