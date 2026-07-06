import AppKit
import ComposableArchitecture
import OrderedCollections
import PTermSettingsShared
import Sharing
import SwiftUI

// Terminal-session rows: per-workspace terminal list, branch grouping/headers,
// the session row itself, and its icon/trailing/status-dot leaves
// (extracted from SidebarListView).
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
  /// threaded down — never re-derived per row (that made every tab-switch re-run
  /// every row body for an identical value).
  var focusedTabID: TerminalTabID?
  var focusedSurfaceID: UUID?
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
            itemStore: itemStore,
            parentStore: store,
            terminalManager: terminalManager,
            surfaceID: entry.surfaceID,
            paneIndex: entry.paneIndex,
            paneCount: entry.paneCount,
            highlightSubtitle: highlightSubtitle,
            selectedWorktreeIDs: selectedWorktreeIDs,
            focusedTabID: focusedTabID,
            focusedSurfaceID: focusedSurfaceID,
            leadingInset: showsBranchHeaders ? leadingInset + SidebarNestLayout.indentStep : leadingInset
          )
        }
      }
    }
  }

  /// Group the terminal entries by their git branch, preserving first-seen
  /// order. Entries with no resolved branch fall into a `nil` group.
  private func branchGroups(_ entries: [SidebarTerminalSessionEntry]) -> [SidebarBranchGroup] {
    let branches = entries.map { entry in
      entry.surfaceID.flatMap { entry.tabState.surfaceGitBranches[$0] }
    }
    return SidebarBranchGrouping.grouped(branches: branches).map { group in
      SidebarBranchGroup(branch: group.branch, entries: group.indices.map { entries[$0] })
    }
  }

  private var terminalEntries: [SidebarTerminalSessionEntry] {
    // A tab with no live surfaces is a phantom (torn-down but not yet reaped, or
    // a stale projection) — it would render a bare "Shell" row with a cached
    // branch. Skip it so the sidebar only shows real terminals.
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

private struct SidebarTerminalSessionEntry: Identifiable {
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
  /// Typed identity — no sentinel-string collision with a real branch name.
  enum ID: Hashable { case branch(String), none }
  let branch: String?
  let entries: [SidebarTerminalSessionEntry]
  var id: ID { branch.map { .branch($0) } ?? .none }
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
  let itemStore: StoreOf<SidebarItemFeature>
  @Bindable var parentStore: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  let surfaceID: UUID?
  let paneIndex: Int?
  let paneCount: Int
  let highlightSubtitle: SidebarHighlightRepoTag?
  let selectedWorktreeIDs: Set<Worktree.ID>
  /// The single app-wide focused terminal (tab + surface), resolved once by the
  /// parent so exactly one row highlights (see `SidebarTerminalSessionRowsView`).
  let focusedTabID: TerminalTabID?
  let focusedSurfaceID: UUID?
  let leadingInset: CGFloat
  @State private var isRenaming = false
  @State private var draftTitle = ""

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
  /// single focused terminal the parent resolved, so at most ONE row can be
  /// selected app-wide — no double-highlight even if two tabs momentarily both
  /// report `isSelected`. A `nil` `surfaceID` marks a single-pane tab row: it
  /// matches by tab, covering the transient window before the tab's active
  /// surface lands.
  private var isSelected: Bool {
    if let surfaceID { return surfaceID == focusedSurfaceID }
    return tabState.id == focusedTabID
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
            selectedWorktreeIDs: selectedWorktreeIDs,
            // A terminal is closed, never deleted — the worktree stays on disk.
            showsDestructive: false
          )
          Divider()
          Button("Close Terminal", systemImage: "xmark", role: .destructive) {
            closeSession()
          }
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

  /// Close this terminal — the pane if it's one of several in a split, else the
  /// whole workspace (tab). Nothing on disk is touched; the worktree stays.
  private func closeSession() {
    guard let worktree = parentStore.state.worktree(for: worktreeID) else { return }
    if let surfaceID, paneCount > 1 {
      terminalManager.handleCommand(.destroySurface(worktree, tabID: tabState.id, surfaceID: surfaceID))
    } else {
      terminalManager.handleCommand(.destroyTab(worktree, tabID: tabState.id))
    }
  }

  private func sessionLabel(renaming: Bool) -> some View {
    Label {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          if renaming {
            SidebarInlineRenameField(
              text: $draftTitle,
              accessibilityLabel: "Rename pane",
              onCommit: commitRename,
              onCancel: { isRenaming = false }
            )
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
            // Glow with a FIXED blur radius whose opacity pulses: the blurred
            // texture is cacheable, unlike the previous animated shadow radius
            // which forced a re-rasterization per frame — at 20-30 running
            // terminals that was 20-30 sustained compositor re-rasters.
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
