import PTermSettingsShared
import SwiftUI

/// Pinned sidebar card surface (glass background, 10pt radius, leading-aligned).
/// Two slots: `header` (top row, left of the inline dismiss X) and `content`
/// (title / description / inline buttons). Pass a non-nil `onDismiss` to add the
/// X button; it lives in the same HStack as `header`, so wide header content
/// (avatars, icons) can't land underneath the dismiss target.
struct SidebarCard<Header: View, Content: View>: View {
  let onDismiss: (() -> Void)?
  var tone: SidebarNoticeTone = .info
  @ViewBuilder let content: () -> Content
  @ViewBuilder let header: () -> Header

  init(
    onDismiss: (() -> Void)? = nil,
    tone: SidebarNoticeTone = .info,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder header: @escaping () -> Header = { EmptyView() }
  ) {
    self.onDismiss = onDismiss
    self.tone = tone
    self.content = content
    self.header = header
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 8) {
        header()
        Spacer(minLength: 0)
        if let onDismiss {
          Button {
            onDismiss()
          } label: {
            Image(systemName: "xmark")
              .font(AppTypography.caption2)
              .foregroundStyle(.secondary)
              .frame(width: 18, height: 18)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .help("Dismiss")
          .accessibilityLabel("Dismiss")
        }
      }
      content()
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(tone.tint.opacity(0.08))
    }
    .glassEffect(.regular, in: .rect(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(tone.tint.opacity(0.22), lineWidth: 1)
    }
    .padding(.horizontal, 10)
    .padding(.bottom, 10)
  }
}

enum SidebarNoticeTone {
  case info
  case success
  case warning
  case danger
  case feature(Color)

  var tint: Color {
    switch self {
    case .info: .teal
    case .success: .green
    case .warning: .orange
    case .danger: .red
    case .feature(let color): color
    }
  }
}

struct SidebarNoticeBadge {
  let title: String
  let tone: SidebarNoticeTone

  init(_ title: String, tone: SidebarNoticeTone) {
    self.title = title
    self.tone = tone
  }
}

struct SidebarNotice {
  let title: String
  let message: String
  let iconSystemName: String?
  let tone: SidebarNoticeTone
  let badge: SidebarNoticeBadge?
  let footnote: String?

  init(
    title: String,
    message: String,
    iconSystemName: String? = nil,
    tone: SidebarNoticeTone = .info,
    badge: SidebarNoticeBadge? = nil,
    footnote: String? = nil
  ) {
    self.title = title
    self.message = message
    self.iconSystemName = iconSystemName
    self.tone = tone
    self.badge = badge
    self.footnote = footnote
  }
}

enum SidebarNoticeKind: Equatable {
  case typographyPersonalization
  case remoteRepositoriesBeta
  case terminalPersistence
  case highlightRelevant
  case nestedWorktrees

  var cardRelevantSinceDate: Date {
    switch self {
    case .typographyPersonalization:
      Date(timeIntervalSince1970: 1_782_777_600)  // 2026-06-30 00:00 UTC.
    case .remoteRepositoriesBeta:
      Date(timeIntervalSince1970: 1_783_036_800)  // 2026-07-03 00:00 UTC.
    case .terminalPersistence:
      Date(timeIntervalSince1970: 1_779_062_400)  // 2026-05-18 00:00 UTC.
    case .highlightRelevant:
      Date(timeIntervalSince1970: 1_778_889_600)  // 2026-05-16 00:00 UTC.
    case .nestedWorktrees:
      Date(timeIntervalSince1970: 1_778_371_200)  // 2026-05-10 00:00 UTC.
    }
  }

  func isDismissed(at dismissedAt: Date) -> Bool {
    SidebarCardRelevance.isDismissed(at: dismissedAt, relevantSince: cardRelevantSinceDate)
  }

  func resolveMode(dismissedAt: Date) -> SidebarNoticeMode {
    isDismissed(at: dismissedAt) ? .hidden : .visible
  }

  func resolveMode(
    groupPinnedRows: Bool,
    groupActiveRows: Bool,
    dismissedAt: Date
  ) -> SidebarNoticeMode {
    guard self == .highlightRelevant else { return resolveMode(dismissedAt: dismissedAt) }
    let anyOn = groupPinnedRows || groupActiveRows
    return anyOn && !isDismissed(at: dismissedAt) ? .visible : .hidden
  }

  func resolveMode(nestWorktreesByBranch: Bool, dismissedAt: Date) -> SidebarNoticeMode {
    guard self == .nestedWorktrees else { return resolveMode(dismissedAt: dismissedAt) }
    return nestWorktreesByBranch && !isDismissed(at: dismissedAt) ? .visible : .hidden
  }

  var notice: SidebarNotice {
    switch self {
    case .typographyPersonalization:
      SidebarNotice(
        title: "Customize your fonts",
        message: "Pick any font installed on your Mac for the app interface and the terminal.",
        iconSystemName: "textformat",
        tone: .info,
        footnote: "Manage in Settings > Typography"
      )
    case .remoteRepositoriesBeta:
      SidebarNotice(
        title: "Remote repositories",
        message: """
          Connect an existing repository over SSH. p/term lists its worktrees and opens \
          terminals on the host while the Mac UI stays local.
          """,
        iconSystemName: "wifi",
        tone: .info,
        badge: SidebarNoticeBadge("Beta", tone: .info)
      )
    case .terminalPersistence:
      SidebarNotice(
        title: "Sessions persist across quits",
        message: """
          Quit p/term anytime. Your agents, scripts, and shells keep running, \
          and reopen exactly where you left off.
          """,
        iconSystemName: "infinity",
        tone: .feature(.purple),
        footnote: "Manage in Settings > General"
      )
    case .highlightRelevant:
      SidebarNotice(
        title: "Pinned and Active at a glance",
        message: """
          Pinned worktrees float to the top, and rows with unread notifications, \
          agents awaiting input, or running scripts surface in a new Active section.
          """,
        iconSystemName: "sparkles",
        tone: .warning,
        footnote: "Toggle in View > Group Relevant Sidebar Rows"
      )
    case .nestedWorktrees:
      SidebarNotice(
        title: "Worktrees nested by branch",
        message: """
          Branches with `/` like `feature/tools/branch` now nest under collapsible groups, \
          sorted alphabetically. Toggle off to restore custom ordering.
          """,
        iconSystemName: "list.bullet.indent",
        tone: .info,
        footnote: "Toggle in View > Nest Worktrees by Branch"
      )
    }
  }

  var transitionToken: String {
    switch self {
    case .typographyPersonalization: "typographyPersonalization:visible"
    case .remoteRepositoriesBeta: "remoteRepositoriesBeta:visible"
    case .terminalPersistence: "terminalPersistence:visible"
    case .highlightRelevant: "highlightRelevant:visible"
    case .nestedWorktrees: "nestedWorktrees:visible"
    }
  }
}

enum SidebarNoticeMode: Equatable {
  case hidden
  case visible
}

/// Standard data-driven notice card used for sidebar onboarding / status cards.
/// Callers pass copy, icon, tone, badge, and optional accessory content instead
/// of creating one-off card view types for each notice.
struct SidebarNoticeCard<Accessory: View>: View {
  let title: String
  let message: String
  let iconSystemName: String?
  let tone: SidebarNoticeTone
  let badge: SidebarNoticeBadge?
  let footnote: String?
  let onDismiss: (() -> Void)?
  @ViewBuilder let accessory: () -> Accessory

  init(
    title: String,
    message: String,
    iconSystemName: String? = nil,
    tone: SidebarNoticeTone = .info,
    badge: SidebarNoticeBadge? = nil,
    footnote: String? = nil,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder accessory: @escaping () -> Accessory
  ) {
    self.title = title
    self.message = message
    self.iconSystemName = iconSystemName
    self.tone = tone
    self.badge = badge
    self.footnote = footnote
    self.onDismiss = onDismiss
    self.accessory = accessory
  }

  init(
    notice: SidebarNotice,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder accessory: @escaping () -> Accessory
  ) {
    self.title = notice.title
    self.message = notice.message
    self.iconSystemName = notice.iconSystemName
    self.tone = notice.tone
    self.badge = notice.badge
    self.footnote = notice.footnote
    self.onDismiss = onDismiss
    self.accessory = accessory
  }

  var body: some View {
    SidebarCard(onDismiss: onDismiss, tone: tone) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(title)
            .font(AppTypography.subheadline)
            .fontWeight(.semibold)
          if let badge {
            SidebarNoticeBadgeView(badge: badge)
          }
        }
        Text(message)
          .font(AppTypography.caption)
          .foregroundStyle(.secondary)
        if let footnote {
          Text(footnote)
            .font(AppTypography.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
        accessory()
      }
    } header: {
      if let iconSystemName {
        Image(systemName: iconSystemName)
          .font(AppTypography.title2)
          .foregroundStyle(tone.tint)
          .accessibilityHidden(true)
      }
    }
  }
}

extension SidebarNoticeCard where Accessory == EmptyView {
  init(
    title: String,
    message: String,
    iconSystemName: String? = nil,
    tone: SidebarNoticeTone = .info,
    badge: SidebarNoticeBadge? = nil,
    footnote: String? = nil,
    onDismiss: (() -> Void)? = nil
  ) {
    self.init(
      title: title,
      message: message,
      iconSystemName: iconSystemName,
      tone: tone,
      badge: badge,
      footnote: footnote,
      onDismiss: onDismiss
    ) {
      EmptyView()
    }
  }

  init(notice: SidebarNotice, onDismiss: (() -> Void)? = nil) {
    self.init(notice: notice, onDismiss: onDismiss) {
      EmptyView()
    }
  }
}

private struct SidebarNoticeBadgeView: View {
  let badge: SidebarNoticeBadge

  var body: some View {
    Text(badge.title)
      .font(AppTypography.caption2)
      .fontWeight(.semibold)
      .foregroundStyle(badge.tone.tint)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(badge.tone.tint.opacity(0.15), in: .capsule)
  }
}

/// Standard title + optional description pair used by every sidebar card today.
/// Callers that need richer composition can pass arbitrary content instead.
struct SidebarCardLabel: View {
  let title: LocalizedStringKey
  let description: LocalizedStringKey?

  init(title: LocalizedStringKey, description: LocalizedStringKey? = nil) {
    self.title = title
    self.description = description
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(AppTypography.subheadline)
        .fontWeight(.semibold)
      if let description {
        Text(description)
          .font(AppTypography.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// Shared "is this card stamp still considered dismissed?" gate.
/// Each card declares its own `relevantSince` cutoff; bumping that
/// date re-shows the card to users who dismissed before it.
enum SidebarCardRelevance {
  static func isDismissed(at dismissedAt: Date, relevantSince: Date) -> Bool {
    dismissedAt >= relevantSince
  }
}
