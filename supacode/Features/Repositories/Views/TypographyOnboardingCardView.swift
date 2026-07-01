import Sharing
import SupacodeSettingsShared
import SwiftUI

/// Bottom-of-sidebar card announcing font personalization (Settings →
/// Typography). Pure FYI: no toggle, no opt-in. Visible until the user
/// dismisses past the relevance cutoff. The priority host
/// (`SidebarBottomCardView`) owns the AppStorage read so SwiftUI re-renders
/// at that layer on dismiss.
struct TypographyOnboardingCardView: View {
  /// Bump on each material content change. Users who dismissed before this date
  /// see the prompt again. Anchored to ship day at 00:00 UTC, the earliest
  /// instant any local timezone reaches the ship-day calendar date, so a
  /// dismiss-on-launch-day satisfies `dismissedAt >= relevantSince`.
  static let cardRelevantSinceDate = Date(timeIntervalSince1970: 1_782_777_600)  // 2026-06-30 00:00 UTC.

  static func isDismissed(at dismissedAt: Date) -> Bool {
    SidebarCardRelevance.isDismissed(at: dismissedAt, relevantSince: cardRelevantSinceDate)
  }

  static func resolveMode(dismissedAt: Date) -> Mode {
    Self.isDismissed(at: dismissedAt) ? .hidden : .visible
  }

  var body: some View {
    TypographyOnboardingCardBody()
  }

  enum Mode: Equatable {
    case hidden
    case visible
  }
}

private struct TypographyOnboardingCardBody: View {
  @Shared(.appStorage("typographyPersonalizationOnboardingDismissedAt"))
  private var dismissedAt: Date = .distantPast

  var body: some View {
    SidebarCard(
      onDismiss: { $dismissedAt.withLock { $0 = .now } },
      content: {
        VStack(alignment: .leading, spacing: 4) {
          SidebarCardLabel(title: "Customize your fonts", description: description)
          Text("Manage in Settings → Typography")
            .font(AppTypography.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
      },
      header: {
        Image(systemName: "textformat")
          .font(AppTypography.title2)
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
      }
    )
  }

  private var description: LocalizedStringKey {
    """
    Pick any font installed on your Mac for the app interface and the terminal.
    """
  }
}
