import ComposableArchitecture
import Sharing
import SwiftUI

/// Mutually-exclusive host for the pinned sidebar bottom card. Priority order:
/// 1. Coding-agent updates available / initial install prompt.
/// 2. Dynamic sidebar notices, newest first.
/// 3. Nothing.
///
/// Owns the `@Shared(.appStorage)` reads as stored properties so SwiftUI
/// observes them at this layer and re-renders when the user dismisses a
/// card. Each notice's `resolveMode(...)` takes the resolved values as
/// parameters so the priority resolver stays pure and testable.
///
/// Toggles (`nestWorktreesByBranch`, `highlightRelevant`) are observed here so
/// the resolver can react, but the permadismiss side-effects on toggle-off
/// live in `SidebarCommands` (where the menu toggles actually fire), so they
/// work regardless of whether the sidebar column is currently visible.
struct SidebarBottomCardView: View {
  let store: StoreOf<AppFeature>
  @Shared(.appStorage("codingAgentsSetupCardDismissedAt"))
  private var agentDismissedAt: Date = .distantPast
  @Shared(.sidebarNestWorktreesByBranch) private var nestWorktreesByBranch: Bool
  @Shared(.appStorage("nestedWorktreesOnboardingDismissedAt"))
  private var onboardingDismissedAt: Date = .distantPast
  @Shared(.sidebarGroupPinnedRows) private var groupPinnedRows: Bool
  @Shared(.sidebarGroupActiveRows) private var groupActiveRows: Bool
  @Shared(.appStorage("highlightRelevantOnboardingDismissedAt"))
  private var highlightDismissedAt: Date = .distantPast
  @Shared(.appStorage("terminalPersistenceOnboardingDismissedAt"))
  private var terminalPersistenceDismissedAt: Date = .distantPast
  @Shared(.appStorage("remoteRepositoriesBetaOnboardingDismissedAt"))
  private var remoteRepositoriesBetaDismissedAt: Date = .distantPast
  @Shared(.appStorage("typographyPersonalizationOnboardingDismissedAt"))
  private var typographyPersonalizationDismissedAt: Date = .distantPast

  var body: some View {
    let agentMode = CodingAgentsSidebarCardView.resolveMode(
      for: store, dismissedAt: agentDismissedAt
    )
    let typographyPersonalizationMode = SidebarNoticeKind.typographyPersonalization.resolveMode(
      dismissedAt: typographyPersonalizationDismissedAt
    )
    let terminalPersistenceMode = SidebarNoticeKind.terminalPersistence.resolveMode(
      dismissedAt: terminalPersistenceDismissedAt
    )
    let remoteRepositoriesBetaMode = SidebarNoticeKind.remoteRepositoriesBeta.resolveMode(
      dismissedAt: remoteRepositoriesBetaDismissedAt
    )
    let highlightMode = SidebarNoticeKind.highlightRelevant.resolveMode(
      groupPinnedRows: groupPinnedRows,
      groupActiveRows: groupActiveRows,
      dismissedAt: highlightDismissedAt
    )
    let onboardingMode = SidebarNoticeKind.nestedWorktrees.resolveMode(
      nestWorktreesByBranch: nestWorktreesByBranch,
      dismissedAt: onboardingDismissedAt
    )
    let resolved = Slot.resolve(
      Slot.Modes(
        agentMode: agentMode,
        typographyPersonalizationMode: typographyPersonalizationMode,
        remoteRepositoriesBetaMode: remoteRepositoriesBetaMode,
        terminalPersistenceMode: terminalPersistenceMode,
        highlightMode: highlightMode,
        onboardingMode: onboardingMode
      )
    )
    Group {
      switch resolved {
      case .none:
        EmptyView()
      case .agent(let mode):
        CodingAgentsSidebarCardView(store: store, mode: mode)
          .transition(Slot.transition)
      case .notice(let kind):
        SidebarNoticeCard(notice: kind.notice, onDismiss: dismissAction(for: kind))
          .transition(Slot.transition)
      }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: resolved.transitionToken)
  }

  private func dismissAction(for kind: SidebarNoticeKind) -> () -> Void {
    {
      switch kind {
      case .typographyPersonalization:
        $typographyPersonalizationDismissedAt.withLock { $0 = .now }
      case .remoteRepositoriesBeta:
        $remoteRepositoriesBetaDismissedAt.withLock { $0 = .now }
      case .terminalPersistence:
        $terminalPersistenceDismissedAt.withLock { $0 = .now }
      case .highlightRelevant:
        $highlightDismissedAt.withLock { $0 = .now }
      case .nestedWorktrees:
        $onboardingDismissedAt.withLock { $0 = .now }
      }
    }
  }

  /// Resolution layer between live state and the rendered branch. Pure so tests
  /// can lock the priority rules and `transitionToken` stability without
  /// exercising the SwiftUI rendering path.
  ///
  /// Priority order (highest first): agent install / updates prompt, then the
  /// newest shipped onboarding card, then older onboarding cards in descending
  /// age. Newest wins so a freshly shipped feature has visibility priority over
  /// older cards that the same user may have already seen.
  enum Slot: Equatable {
    case none
    case agent(CodingAgentsSidebarCardView.Mode)
    case notice(SidebarNoticeKind)

    static let transition: AnyTransition = .move(edge: .bottom).combined(with: .opacity)

    /// Bundles `resolve`'s inputs so the function stays under the parameter-count
    /// lint limit; fields stay independent named values, not a tuple.
    struct Modes: Equatable {
      let agentMode: CodingAgentsSidebarCardView.Mode
      let typographyPersonalizationMode: SidebarNoticeMode
      let remoteRepositoriesBetaMode: SidebarNoticeMode
      let terminalPersistenceMode: SidebarNoticeMode
      let highlightMode: SidebarNoticeMode
      let onboardingMode: SidebarNoticeMode
    }

    static func resolve(_ modes: Modes) -> Slot {
      switch modes.agentMode {
      case .updatesAvailable, .promptInstall: return .agent(modes.agentMode)
      case .hidden: break
      }
      let notices: [(SidebarNoticeKind, SidebarNoticeMode)] = [
        (.remoteRepositoriesBeta, modes.remoteRepositoriesBetaMode),
        (.typographyPersonalization, modes.typographyPersonalizationMode),
        (.terminalPersistence, modes.terminalPersistenceMode),
        (.highlightRelevant, modes.highlightMode),
        (.nestedWorktrees, modes.onboardingMode),
      ]
      return notices.first { $0.1 == .visible }.map { .notice($0.0) } ?? .none
    }

    /// Hashable identity used by `.animation(_:value:)`. Same-variant state
    /// changes share a token so the entry transition only fires when the
    /// rendered branch actually changes. Keyed off case names rather than
    /// `SkillAgent.rawValue` so a future user-facing rename of an agent's
    /// raw value doesn't silently change transition stability.
    var transitionToken: String {
      switch self {
      case .none: "none"
      case .agent(.updatesAvailable(let agents)):
        "agent:updates:" + agents.map { String(describing: $0) }.sorted().joined(separator: ",")
      case .agent(.promptInstall): "agent:promptInstall"
      case .agent(.hidden): "agent:hidden"
      case .notice(let kind): kind.transitionToken
      }
    }
  }
}
