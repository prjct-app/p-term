import Foundation
import PTermSettingsShared
import Testing

@testable import p_term

@MainActor
struct SidebarBottomCardTests {
  @Test func agentUpdatesWinOverEverything() {
    let resolved = SidebarBottomCardView.Slot.resolve(
      SidebarBottomCardView.Slot.Modes(
        agentMode: .updatesAvailable([.claude]),
        typographyPersonalizationMode: .visible,
        remoteRepositoriesBetaMode: .visible,
        terminalPersistenceMode: .visible,
        highlightMode: .visible,
        onboardingMode: .visible
      )
    )
    #expect(resolved == .agent(.updatesAvailable([.claude])))
  }

  @Test func agentPromptWinsOverEverything() {
    let resolved = SidebarBottomCardView.Slot.resolve(
      SidebarBottomCardView.Slot.Modes(
        agentMode: .promptInstall,
        typographyPersonalizationMode: .visible,
        remoteRepositoriesBetaMode: .visible,
        terminalPersistenceMode: .visible,
        highlightMode: .visible,
        onboardingMode: .visible
      )
    )
    #expect(resolved == .agent(.promptInstall))
  }

  @Test func remoteRepositoriesBetaWinsOverOlderOnboarding() {
    let resolved = SidebarBottomCardView.Slot.resolve(
      SidebarBottomCardView.Slot.Modes(
        agentMode: .hidden,
        typographyPersonalizationMode: .visible,
        remoteRepositoriesBetaMode: .visible,
        terminalPersistenceMode: .visible,
        highlightMode: .visible,
        onboardingMode: .visible
      )
    )
    #expect(resolved == .notice(.remoteRepositoriesBeta))
  }

  @Test func typographyPersonalizationWinsOverOlderOnboarding() {
    let resolved = SidebarBottomCardView.Slot.resolve(
      SidebarBottomCardView.Slot.Modes(
        agentMode: .hidden,
        typographyPersonalizationMode: .visible,
        remoteRepositoriesBetaMode: .hidden,
        terminalPersistenceMode: .visible,
        highlightMode: .visible,
        onboardingMode: .visible
      )
    )
    #expect(resolved == .notice(.typographyPersonalization))
  }

  @Test func terminalPersistenceWinsOverHighlightAndNested() {
    let resolved = SidebarBottomCardView.Slot.resolve(
      SidebarBottomCardView.Slot.Modes(
        agentMode: .hidden,
        typographyPersonalizationMode: .hidden,
        remoteRepositoriesBetaMode: .hidden,
        terminalPersistenceMode: .visible,
        highlightMode: .visible,
        onboardingMode: .visible
      )
    )
    #expect(resolved == .notice(.terminalPersistence))
  }

  @Test func highlightWinsOverNestedOnboarding() {
    let resolved = SidebarBottomCardView.Slot.resolve(
      SidebarBottomCardView.Slot.Modes(
        agentMode: .hidden,
        typographyPersonalizationMode: .hidden,
        remoteRepositoriesBetaMode: .hidden,
        terminalPersistenceMode: .hidden,
        highlightMode: .visible,
        onboardingMode: .visible
      )
    )
    #expect(resolved == .notice(.highlightRelevant))
  }

  @Test func nestedOnboardingShowsWhenHigherPriorityDismissed() {
    let resolved = SidebarBottomCardView.Slot.resolve(
      SidebarBottomCardView.Slot.Modes(
        agentMode: .hidden,
        typographyPersonalizationMode: .hidden,
        remoteRepositoriesBetaMode: .hidden,
        terminalPersistenceMode: .hidden,
        highlightMode: .hidden,
        onboardingMode: .visible
      )
    )
    #expect(resolved == .notice(.nestedWorktrees))
  }

  @Test func noneWhenAllHidden() {
    let resolved = SidebarBottomCardView.Slot.resolve(
      SidebarBottomCardView.Slot.Modes(
        agentMode: .hidden,
        typographyPersonalizationMode: .hidden,
        remoteRepositoriesBetaMode: .hidden,
        terminalPersistenceMode: .hidden,
        highlightMode: .hidden,
        onboardingMode: .hidden
      )
    )
    #expect(resolved == SidebarBottomCardView.Slot.none)
  }

  @Test func typographyPersonalizationTransitionTokenIsStable() {
    #expect(
      SidebarBottomCardView.Slot.notice(.typographyPersonalization).transitionToken
        == "typographyPersonalization:visible"
    )
  }

  @Test func terminalPersistenceTransitionTokenIsStable() {
    #expect(
      SidebarBottomCardView.Slot.notice(.terminalPersistence).transitionToken == "terminalPersistence:visible"
    )
  }

  @Test func remoteRepositoriesBetaTransitionTokenIsStable() {
    #expect(
      SidebarBottomCardView.Slot.notice(.remoteRepositoriesBeta).transitionToken == "remoteRepositoriesBeta:visible"
    )
  }

  @Test func agentVariantStableAcrossSkillAgentOrder() {
    let lhs = SidebarBottomCardView.Slot.agent(.updatesAvailable([.claude, .codex])).transitionToken
    let rhs = SidebarBottomCardView.Slot.agent(.updatesAvailable([.codex, .claude])).transitionToken
    #expect(lhs == rhs)
  }

  @Test func onboardingTransitionTokenUsesNestedWorktreesPrefix() {
    #expect(SidebarBottomCardView.Slot.notice(.nestedWorktrees).transitionToken == "nestedWorktrees:visible")
  }

  @Test func highlightOnboardingTransitionTokenIsStable() {
    #expect(
      SidebarBottomCardView.Slot.notice(.highlightRelevant).transitionToken == "highlightRelevant:visible"
    )
  }

  @Test func typographyPersonalizationCardHiddenWhenDismissedAfterRelevance() {
    let afterRelevance = SidebarNoticeKind.typographyPersonalization.cardRelevantSinceDate.addingTimeInterval(1)
    #expect(SidebarNoticeKind.typographyPersonalization.resolveMode(dismissedAt: afterRelevance) == .hidden)
  }

  @Test func typographyPersonalizationCardVisibleWhenNeverDismissed() {
    #expect(SidebarNoticeKind.typographyPersonalization.resolveMode(dismissedAt: .distantPast) == .visible)
  }

  @Test func highlightCardHiddenWhenBothTogglesOff() {
    #expect(
      SidebarNoticeKind.highlightRelevant.resolveMode(
        groupPinnedRows: false,
        groupActiveRows: false,
        dismissedAt: .distantPast
      ) == .hidden
    )
  }

  @Test func highlightCardVisibleWhenOnlyPinnedOn() {
    #expect(
      SidebarNoticeKind.highlightRelevant.resolveMode(
        groupPinnedRows: true,
        groupActiveRows: false,
        dismissedAt: .distantPast
      ) == .visible
    )
  }

  @Test func highlightCardVisibleWhenOnlyActiveOn() {
    #expect(
      SidebarNoticeKind.highlightRelevant.resolveMode(
        groupPinnedRows: false,
        groupActiveRows: true,
        dismissedAt: .distantPast
      ) == .visible
    )
  }

  @Test func highlightCardHiddenWhenDismissedAfterRelevance() {
    let afterRelevance = SidebarNoticeKind.highlightRelevant.cardRelevantSinceDate.addingTimeInterval(1)
    #expect(
      SidebarNoticeKind.highlightRelevant.resolveMode(
        groupPinnedRows: true,
        groupActiveRows: true,
        dismissedAt: afterRelevance
      ) == .hidden
    )
  }

  @Test func highlightCardHiddenWhenDismissedAtRelevanceBoundary() {
    // The relevance date must be on-or-before the ship date so a dismiss on
    // release day stays sticky. A future-dated relevance date would resurface
    // the card the next time SwiftUI re-rendered it.
    let atBoundary = SidebarNoticeKind.highlightRelevant.cardRelevantSinceDate
    #expect(
      SidebarNoticeKind.highlightRelevant.resolveMode(
        groupPinnedRows: true,
        groupActiveRows: true,
        dismissedAt: atBoundary
      ) == .hidden
    )
  }
}
