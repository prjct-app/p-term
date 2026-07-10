import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

/// Tight, single-scale layout for the sidebar list.
///
/// Type ladder (pt): section 10 · child 12 · workspace/actions 13.
/// Vertical: 1–2 pt insets, shared min height — no special tall workspace rows.
///
/// Nest: workspace (0) → terminal/CTA (indentStep). Project header only if multi-worktree.
enum SidebarNestLayout {
  static let indentStep: CGFloat = 12
  static let rowSpacing: CGFloat = 6
  static let chevronSlot: CGFloat = 10
  static let trailingInset: CGFloat = 6
  /// Same vertical inset for parent and child — kills the gappy rhythm.
  static let rowVerticalInset: CGFloat = 1
  static let rowMinHeight: CGFloat = 20
  static var workspaceUnderProject: CGFloat { indentStep }
  static func terminalUnderWorkspace(workspaceLeading: CGFloat) -> CGFloat {
    workspaceLeading + indentStep
  }
}

/// Repo identity carried alongside a sidebar row so the highlight sections
/// can render a colored `repo · worktree` subtitle that mirrors the window
/// toolbar. `nil` on a row keeps the standard per-repo subtitle.
struct SidebarHighlightRepoTag: Equatable, Hashable, Sendable {
  let repoName: String
  let repoColor: RepositoryColor?
  /// `[user@]host[:port]` when the repo is remote, else nil; shown as `· host`
  /// plus a `wifi` glyph in the subtitle.
  let hostInfo: String?
}

struct SidebarItemView: View {
  let store: StoreOf<SidebarItemFeature>
  let hideSubtitle: Bool
  let hideSubtitleOnMatch: Bool
  let showsPullRequestInfo: Bool
  let shortcutHint: String?
  /// Trailing branch-component label injected by the branch-nesting renderer so
  /// a row nested under a `feature/tools` header reads as `a` instead of the
  /// full `feature/tools/a`. `nil` keeps the original branch name.
  var displayNameOverride: String?
  /// Number of group-header ancestors above this row, used by the renderer
  /// to apply a per-level leading indent. `0` keeps the existing baseline.
  var nestDepth: Int = 0
  /// Non-nil only inside the global Pinned / Active sections.
  var highlightSubtitle: SidebarHighlightRepoTag?
  /// Number of secondary windows currently open for this workspace (see `OpenWindowRegistry`).
  /// `0` is the common case and renders no badge.
  var openWindowCount: Int = 0

  @State private var isRenaming = false
  @State private var draftTitle = ""
  @FocusState private var renameFieldFocused: Bool
  @Environment(\.commitInlineRenameAction) private var commitInlineRenameAction

  var body: some View {
    let resolved = ResolvedRowDisplay(
      kind: store.kind,
      branchName: displayNameOverride ?? store.branchName,
      worktreeName: store.sidebarDisplayName,
      isMainWorktree: store.isMainWorktree,
      isPinned: store.isPinned,
      hideSubtitle: hideSubtitle,
      hideSubtitleOnMatch: hideSubtitleOnMatch,
      highlightSubtitle: highlightSubtitle,
      customTitle: store.customTitle,
      customTint: store.customTint
    )

    Label {
      HStack(spacing: 8) {
        if isRenaming {
          TextField("Title", text: $draftTitle)
            .textFieldStyle(.plain)
            .font(AppTypography.body)
            .focused($renameFieldFocused)
            .onSubmit { commitRename(currentName: resolved.name) }
            .onExitCommand { isRenaming = false }
            .onAppear { renameFieldFocused = true }
            .onChange(of: renameFieldFocused) { _, focused in
              if !focused { commitRename(currentName: resolved.name) }
            }
        } else {
          TitleView(
            name: resolved.name,
            subtitle: resolved.subtitle,
            accent: resolved.accent,
            customTint: store.customTint,
            isLifecycleBusy: store.lifecycle.isBusy,
            isTaskRunning: store.isTaskRunning
          )
          .equatable()
          // `Button` can't discriminate click count, so double-click-to-rename is a
          // deliberate, narrow exception to preferring `Button` over `onTapGesture`.
          .onTapGesture(count: 2) {
            draftTitle = resolved.name
            isRenaming = true
          }
        }
        Spacer(minLength: 0)
        TrailingView(
          store: store,
          shortcutHint: shortcutHint,
          showsPullRequestInfo: showsPullRequestInfo,
          openWindowCount: openWindowCount
        )
      }
    } icon: {
      IconView(
        isFolder: store.kind == .folder,
        isRemote: store.isRemote,
        isMissing: store.isMissing,
        branchName: store.branchName,
        pullRequest: store.pullRequest,
        showsPullRequestInfo: showsPullRequestInfo,
        lifecycle: store.lifecycle
      )
    }
    .labelStyle(.verticallyCentered)
    .listRowInsets(.leading, CGFloat(nestDepth) * SidebarNestLayout.indentStep)
    .listRowInsets(.trailing, 4)
    .listRowInsets(.vertical, 6)
  }

  /// `onSubmit` and the `renameFieldFocused` `onChange` (Tab/click-away) can both fire for the
  /// same commit; the `isRenaming` guard makes the second call a no-op instead of a double-send.
  private func commitRename(currentName: String) {
    guard isRenaming else { return }
    isRenaming = false
    let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != currentName else { return }
    commitInlineRenameAction(trimmed)
  }
}

struct ResolvedRowDisplay: Equatable {
  enum Subtitle: Equatable {
    case none
    /// Standard per-repo subtitle. Rendered in the row's accent color.
    case plain(String)
    /// Highlight-section subtitle: `repo · host · trail`. `repo` paints with
    /// `repoColor`, `trail` with the row's accent; `hostInfo` (when set) inserts
    /// `· host` plus a `wifi` glyph. `trail == nil` collapses to just the repo.
    case highlight(repo: String, repoColor: RepositoryColor?, trail: String?, hostInfo: String?)
  }

  let name: String
  let subtitle: Subtitle
  let accent: WorktreeAccent

  init(
    kind: SidebarItemFeature.State.Kind,
    branchName: String,
    worktreeName: String?,
    isMainWorktree: Bool,
    isPinned: Bool,
    hideSubtitle: Bool,
    hideSubtitleOnMatch: Bool,
    highlightSubtitle: SidebarHighlightRepoTag? = nil,
    customTitle: String? = nil,
    customTint: RepositoryColor? = nil
  ) {
    self.accent =
      if isMainWorktree { .main } else if isPinned { .pinned } else { .default }

    // User override (trimmed) takes precedence over derived names.
    let resolvedCustom = SidebarDisplayName.resolved(custom: customTitle, fallback: nil)
    let hasCustomTitle = resolvedCustom != nil

    if kind == .folder {
      self.name = resolvedCustom ?? branchName
      // Folder rows ARE the repo; a remote folder's `wifi` glyph rides the title
      // line (via `TitleView`), so there's no subtitle.
      self.subtitle = .none
      return
    }

    // Product model: the row is a *workspace* (terminal home). Git branch is
    // metadata shown in the title/subtitle — not a "worktree" product noun.
    // `worktreeName` is only the folder-derived label when it differs from the branch.
    let folderLabel = worktreeName.flatMap { $0.isEmpty ? nil : $0 }
    let effectiveFolderLabel = folderLabel ?? branchName
    self.name = resolvedCustom ?? branchName

    let branchLastComponent = branchName.split(separator: "/").last.map(String.init) ?? branchName
    let isMatch = effectiveFolderLabel == branchLastComponent
    // Once a user types a custom title, they've lost the visual cue that the auto-derived name was
    // providing, so we always render the subtitle even when it would otherwise collapse on match.
    let shouldHideOnMatch = hideSubtitleOnMatch && !hasCustomTitle && isMatch

    if let highlightSubtitle {
      // Active/Pinned: `project · git-branch` (or project only when title already is the branch).
      let trail: String?
      if shouldHideOnMatch {
        trail = nil
      } else if isMainWorktree {
        // Main checkout: show the actual branch name (usually `main`/`master`), never "Default".
        trail = branchName.isEmpty ? nil : branchName
      } else if let folderLabel, folderLabel != branchName {
        trail = folderLabel
      } else {
        trail = nil
      }
      self.subtitle = .highlight(
        repo: highlightSubtitle.repoName,
        repoColor: highlightSubtitle.repoColor,
        trail: trail,
        hostInfo: highlightSubtitle.hostInfo
      )
      return
    }

    if hideSubtitle || shouldHideOnMatch {
      self.subtitle = .none
    } else {
      // Repo sections: secondary line is git context when useful.
      self.subtitle = .plain(effectiveFolderLabel)
    }
  }
}

enum SidebarCheckBadgeState: Equatable {
  case passing
  case failing
  case inProgress

  var symbolName: String {
    switch self {
    case .passing: "checkmark"
    case .failing: "xmark"
    case .inProgress: "ellipsis"
    }
  }

  var color: Color {
    switch self {
    case .passing: .green
    case .failing: .red
    case .inProgress: .yellow
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .passing: "Checks passed"
    case .failing: "Checks failed"
    case .inProgress: "Checks in progress"
    }
  }
}

enum SidebarPullRequestIcon: Equatable {
  case branch
  case open
  case draft
  case queued
  case merged
  case closed

  static func resolve(_ pullRequest: GithubPullRequest?) -> Self {
    guard let pullRequest else { return .branch }
    switch pullRequest.state.uppercased() {
    case "MERGED": return .merged
    case "CLOSED": return .closed
    case "OPEN" where pullRequest.isDraft: return .draft
    case "OPEN" where PullRequestMergeQueueStatus(pullRequest: pullRequest) != nil: return .queued
    case "OPEN": return .open
    default: return .branch
    }
  }

  var assetName: String {
    switch self {
    case .branch: "git-branch"
    case .open: "git-pull-request"
    case .draft: "git-pull-request-draft"
    case .queued: "git-merge-queue"
    case .merged: "git-merge"
    case .closed: "git-pull-request-closed"
    }
  }

  var color: AnyShapeStyle {
    switch self {
    case .branch: AnyShapeStyle(.secondary)
    case .open: AnyShapeStyle(.green)
    case .draft: AnyShapeStyle(.tertiary)
    case .queued: AnyShapeStyle(.brown)
    case .merged: AnyShapeStyle(.purple)
    case .closed: AnyShapeStyle(.red)
    }
  }
}

private func resolveCheckBadgeState(_ pullRequest: GithubPullRequest?) -> SidebarCheckBadgeState? {
  guard let checks = pullRequest?.statusCheckRollup?.checks, !checks.isEmpty else { return nil }
  let breakdown = PullRequestCheckBreakdown(checks: checks)
  if breakdown.failed > 0 { return .failing }
  if breakdown.inProgress > 0 || breakdown.expected > 0 { return .inProgress }
  return .passing
}

private struct TitleView: View, Equatable {
  let name: String
  let subtitle: ResolvedRowDisplay.Subtitle
  let accent: WorktreeAccent
  /// User-supplied row tint. When set, paints the title; otherwise the title uses the default.
  let customTint: RepositoryColor?
  let isLifecycleBusy: Bool
  let isTaskRunning: Bool
  // `==` ignores @Environment; SwiftUI tracks env changes separately.
  @Environment(\.backgroundProminence) private var backgroundProminence

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.name == rhs.name
      && lhs.subtitle == rhs.subtitle
      && lhs.accent == rhs.accent
      && lhs.customTint == rhs.customTint
      && lhs.isLifecycleBusy == rhs.isLifecycleBusy
      && lhs.isTaskRunning == rhs.isTaskRunning
  }

  var body: some View {
    let isBusy = isLifecycleBusy || isTaskRunning
    let isEmphasized = backgroundProminence == .increased
    // Titles stay neutral: selected/emphasized = primary, else muted.
    // Color belongs on indicators only — never on the title string.
    let titleStyle: AnyShapeStyle =
      isEmphasized ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    let metaStyle: AnyShapeStyle = AnyShapeStyle(.tertiary)
    VStack(alignment: .leading, spacing: 0) {
      Text(name)
        .font(AppTypography.body.weight(isEmphasized ? .medium : .regular))
        .foregroundStyle(titleStyle)
        .lineLimit(1)
        .shimmer(isActive: isBusy)
      switch subtitle {
      case .none:
        EmptyView()
      case .plain(let text):
        Text(text)
          .font(AppTypography.footnote)
          .foregroundStyle(metaStyle)
          .lineLimit(1)
      case .highlight(let repo, _, let trail, let hostInfo):
        HStack(spacing: 0) {
          Text(repo)
            .foregroundStyle(metaStyle)
            .lineLimit(1)
            .layoutPriority(1)
          if let hostInfo {
            Image(systemName: "wifi")
              .imageScale(.small)
              .foregroundStyle(.tertiary)
              .help(hostInfo)
              .accessibilityLabel("Remote host \(hostInfo)")
              .padding(.leading, 3)
              .layoutPriority(1)
          }
          if let trail {
            Text(" · ")
              .foregroundStyle(.tertiary)
              .lineLimit(1)
            Text(trail)
              .foregroundStyle(metaStyle)
              .lineLimit(1)
          }
        }
        .font(AppTypography.footnote)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trail.map { "\(repo), \($0)" } ?? repo)
      }
    }
  }
}

private struct IconView: View {
  let isFolder: Bool
  let isRemote: Bool
  let isMissing: Bool
  let branchName: String
  let pullRequest: GithubPullRequest?
  let showsPullRequestInfo: Bool
  let lifecycle: SidebarItemFeature.State.Lifecycle

  var body: some View {
    let display = WorktreePullRequestDisplay(
      worktreeName: branchName,
      pullRequest: showsPullRequestInfo ? pullRequest : nil,
    )
    IconContent(
      isFolder: isFolder,
      isRemote: isRemote,
      isMissing: isMissing,
      icon: SidebarPullRequestIcon.resolve(display.pullRequest),
      checkBadgeState: resolveCheckBadgeState(display.pullRequest),
      rowState: IconRowState(lifecycle),
    )
    .equatable()
  }
}

enum IconRowState: Equatable {
  case idle
  case pending
  case archiving
  case deleting

  init(_ lifecycle: SidebarItemFeature.State.Lifecycle) {
    switch lifecycle {
    case .idle: self = .idle
    case .pending: self = .pending
    case .archiving: self = .archiving
    case .deleting, .deletingScript: self = .deleting
    }
  }
}

private struct IconContent: View, Equatable {
  let isFolder: Bool
  let isRemote: Bool
  let isMissing: Bool
  let icon: SidebarPullRequestIcon
  let checkBadgeState: SidebarCheckBadgeState?
  let rowState: IconRowState
  // `==` ignores @Environment; SwiftUI tracks env changes separately.
  @Environment(\.backgroundProminence) private var backgroundProminence

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.isFolder == rhs.isFolder
      && lhs.isRemote == rhs.isRemote
      && lhs.isMissing == rhs.isMissing
      && lhs.icon == rhs.icon
      && lhs.checkBadgeState == rhs.checkBadgeState
      && lhs.rowState == rhs.rowState
  }

  private var isEmphasized: Bool {
    backgroundProminence == .increased
  }

  private var isSystemImage: Bool {
    rowState != .idle || isFolder || isMissing
  }

  private var folderIconName: String {
    if isMissing { return "exclamationmark.triangle.fill" }
    switch rowState {
    case .pending: return "truck.box.badge.clock"
    case .archiving: return "archivebox"
    case .deleting: return "trash"
    case .idle: return "folder"
    }
  }

  private var folderColor: AnyShapeStyle {
    guard !isEmphasized else { return AnyShapeStyle(.secondary) }
    if isMissing { return AnyShapeStyle(.orange) }
    switch rowState {
    case .pending: return AnyShapeStyle(.blue)
    case .archiving: return AnyShapeStyle(.orange)
    case .deleting: return AnyShapeStyle(.red)
    case .idle: return AnyShapeStyle(.secondary)
    }
  }

  private var accessibilityLabel: String? {
    if isMissing { return "Working directory missing" }
    switch rowState {
    case .pending: return "Creating"
    case .archiving: return "Archiving"
    case .deleting: return "Deleting"
    case .idle: return nil
    }
  }

  var body: some View {
    Group {
      if isSystemImage {
        Image(systemName: folderIconName)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .fontWeight(.semibold)
          .foregroundStyle(folderColor)
          .opacity(isEmphasized ? 1 : 0.6)
      } else {
        Image(icon.assetName)
          .renderingMode(.template)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .foregroundStyle(isEmphasized ? AnyShapeStyle(.secondary) : icon.color)
          .opacity(isEmphasized ? 1 : 0.6)
      }
    }
    .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    .overlay(alignment: .bottomTrailing) {
      if let checkBadgeState, !isSystemImage {
        let badgeColor = AnyShapeStyle(checkBadgeState.color)
        let background = AnyShapeStyle(.windowBackground)
        Image(systemName: checkBadgeState.symbolName)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .symbolVariant(.circle.fill)
          .symbolRenderingMode(.palette)
          .fontWeight(.black)
          .frame(width: AppChromeMetrics.Sidebar.rowBadgeSize, height: AppChromeMetrics.Sidebar.rowBadgeSize)
          .foregroundStyle(
            isEmphasized ? badgeColor : background,
            isEmphasized ? background : badgeColor,
          )
          .background(in: Circle())
          .accessibilityLabel(checkBadgeState.accessibilityLabel)
          .offset(x: 2, y: 2)
      }
    }
    .accessibilityLabel(accessibilityLabel ?? "")
    .accessibilityHidden(accessibilityLabel == nil)
  }
}

private struct TrailingView: View {
  let store: StoreOf<SidebarItemFeature>
  let shortcutHint: String?
  let showsPullRequestInfo: Bool
  var openWindowCount: Int = 0

  var body: some View {
    let hasHint = shortcutHint != nil
    let display = WorktreePullRequestDisplay(
      worktreeName: store.branchName,
      pullRequest: showsPullRequestInfo ? store.pullRequest : nil,
    )
    let prText = display.pullRequestBadgeStyle?.text
    let agents = store.agents
    let scriptColors = store.runningScripts.map(\.tint)
    let showsNotificationIndicator = store.hasUnseenNotifications
    let notifications = Array(store.notifications)
    let added = store.addedLines ?? 0
    let removed = store.removedLines ?? 0
    let hasStats = added + removed > 0
    let hasStatus = !scriptColors.isEmpty || showsNotificationIndicator
    // A window group's dot rides the SAME two leaf-local flags `SidebarActiveClassification`
    // already reads (`hasUnseenNotifications`, `hasAgentAwaitingInput`) — no new per-instance
    // state needed, since `SidebarItemFeature.State` is per-worktree, not per-window-instance.
    let windowGroupNeedsAttention =
      openWindowCount >= 1 && (store.hasUnseenNotifications || store.hasAgentAwaitingInput)

    // Cross-fade via opacity so flipping ⌘ doesn't snap the row.
    ZStack(alignment: .trailing) {
      HStack(spacing: AppChromeMetrics.Sidebar.accessorySpacing) {
        if openWindowCount >= 1 {
          OpenWindowCountBadge(count: openWindowCount, needsAttention: windowGroupNeedsAttention)
            .equatable()
        }
        if store.kind == .folder, let host = store.host {
          Image(systemName: "wifi")
            .imageScale(.small)
            .font(AppTypography.subheadline)
            .foregroundStyle(.secondary)
            .help(host.displayAuthority)
            .accessibilityLabel("Remote host \(host.displayAuthority)")
        }
        if hasStats {
          DiffStatsContent(addedLines: added, removedLines: removed)
            .equatable()
        }
        if let prText {
          PullRequestBadgeContent(text: prText)
            .equatable()
        }
        if !agents.isEmpty {
          RunningAgentsBadgeContent(agents: agents)
            .equatable()
        }
        if hasStatus {
          StatusIndicator(
            runningScriptColors: scriptColors,
            showsNotificationIndicator: showsNotificationIndicator,
            notifications: notifications,
          )
          .equatable()
        }
      }
      // Title takes the squeeze under narrow widths, not the counters.
      .fixedSize(horizontal: true, vertical: false)
      .opacity(hasHint ? 0 : 1)
      .allowsHitTesting(!hasHint)

      Text(shortcutHint ?? "")
        .font(AppTypography.caption)
        .foregroundStyle(.secondary)
        .opacity(hasHint ? 1 : 0)
    }
    .animation(.easeInOut(duration: TerminalTabBarMetrics.fadeAnimationDuration), value: hasHint)
  }
}

/// Trailing badge showing how many secondary windows are open for this workspace (see
/// `OpenWindowRegistry`). Only rendered when `count >= 1`; the common case shows nothing.
/// `needsAttention` overlays a pinging dot — reusing `SidebarPingDot`, this codebase's existing
/// "something is actively happening" primitive, rather than the quieter static notification dot,
/// since the ask here was specifically for something attention-grabbing.
private struct OpenWindowCountBadge: View, Equatable {
  let count: Int
  let needsAttention: Bool

  var body: some View {
    Label {
      Text("\(count)")
    } icon: {
      Image(systemName: "macwindow")
    }
    .labelStyle(.titleAndIcon)
    .font(AppTypography.caption)
    .foregroundStyle(.secondary)
    .overlay(alignment: .topTrailing) {
      if needsAttention {
        SidebarPingDot(
          color: .orange,
          size: AppChromeMetrics.Sidebar.statusDotSize,
          showsSolidCenter: true
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This workspace's open windows need your attention")
        .offset(x: 4, y: -4)
      }
    }
    .help("\(count) window\(count == 1 ? "" : "s") open for this workspace")
    .accessibilityLabel("\(count) window\(count == 1 ? "" : "s") open")
    .transition(.blurReplace)
  }
}

private struct PullRequestBadgeContent: View, Equatable {
  let text: String

  var body: some View {
    Text(text)
      .font(AppTypography.caption)
      .foregroundStyle(.secondary)
      .transition(.blurReplace)
  }
}

private struct RunningAgentsBadgeContent: View, Equatable {
  let agents: [AgentPresenceFeature.AgentInstance]

  var body: some View {
    AgentAvatarGroupView(instances: agents, size: AppChromeMetrics.Sidebar.rowIconSize)
  }
}

/// Git diff stats next to the branch (`+12` / `-3`). Shared by the classic
/// leaf row and the workspace parent in Active/Pinned.
struct DiffStatsContent: View, Equatable {
  let addedLines: Int
  let removedLines: Int
  // `==` ignores @Environment; SwiftUI tracks env changes separately.
  @Environment(\.backgroundProminence) private var backgroundProminence

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.addedLines == rhs.addedLines && lhs.removedLines == rhs.removedLines
  }

  var body: some View {
    let isEmphasized = backgroundProminence == .increased
    HStack(spacing: 2) {
      if addedLines > 0 {
        Text("+\(addedLines)")
          .foregroundStyle(isEmphasized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
      }
      if removedLines > 0 {
        Text("-\(removedLines)")
          .foregroundStyle(isEmphasized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
      }
    }
    .font(AppTypography.caption.weight(.medium))
    .monospacedDigit()
    .transition(.blurReplace)
    .accessibilityLabel("\(addedLines) lines added, \(removedLines) lines removed")
  }
}

private struct StatusIndicator: View, Equatable {
  let runningScriptColors: [RepositoryColor]
  let showsNotificationIndicator: Bool
  let notifications: [WorktreeTerminalNotification]
  // `==` ignores @Environment; SwiftUI tracks env changes separately.
  @Environment(\.backgroundProminence) private var backgroundProminence
  @Environment(\.focusNotificationAction) private var focusNotificationAction: (WorktreeTerminalNotification) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.runningScriptColors == rhs.runningScriptColors
      && lhs.showsNotificationIndicator == rhs.showsNotificationIndicator
      && lhs.notifications == rhs.notifications
  }

  var body: some View {
    let isEmphasized = backgroundProminence == .increased
    let isRunning = !runningScriptColors.isEmpty
    if isRunning || showsNotificationIndicator {
      ZStack {
        if isRunning {
          SidebarPingMultiColorDot(
            colors: runningScriptColors,
            isEmphasized: isEmphasized,
            size: AppChromeMetrics.Sidebar.statusDotSize,
            showsSolidCenter: !showsNotificationIndicator
          )
        }
        if showsNotificationIndicator {
          NotificationPopoverButton(notifications: notifications) {
            Circle()
              .fill(.orange)
              .frame(
                width: AppChromeMetrics.Sidebar.statusDotSize,
                height: AppChromeMetrics.Sidebar.statusDotSize
              )
              .accessibilityLabel("Unread notifications")
          }
          .zIndex(1)
        }
      }
      .transition(.blurReplace)
    }
  }
}

private nonisolated let notificationEnvironmentLogger = PTermLogger("Notifications")

extension EnvironmentValues {
  @Entry var focusNotificationAction: (WorktreeTerminalNotification) -> Void = { _ in
    notificationEnvironmentLogger.warning("focusNotificationAction called but was never set in the environment.")
  }

  /// Commits a double-click-rename's new title. Set by `SidebarItemBody` (which holds the
  /// `RepositoriesFeature` parent store `SidebarItemView` itself doesn't have access to).
  @Entry var commitInlineRenameAction: (String) -> Void = { _ in
    notificationEnvironmentLogger.warning("commitInlineRenameAction called but was never set in the environment.")
  }
}
