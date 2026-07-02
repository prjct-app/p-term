import Foundation
import PTermSettingsShared
import Sharing

struct CommandPaletteItem: Identifiable, Equatable {
  static let defaultPriorityTier = 100

  let id: String
  let title: String
  let subtitle: String?
  let kind: Kind
  let priorityTier: Int

  init(
    id: String,
    title: String,
    subtitle: String?,
    kind: Kind,
    priorityTier: Int = defaultPriorityTier
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.kind = kind
    self.priorityTier = priorityTier
  }

  enum Kind: Equatable {
    case checkForUpdates
    case openRepository
    case addRemoteRepository
    case worktreeSelect(Worktree.ID)
    case openSettings
    case newWorktree
    case removeWorktree(Worktree.ID, Repository.ID)
    case archiveWorktree(Worktree.ID, Repository.ID)
    case renameBranch(Worktree.ID, Repository.ID)
    case viewArchivedWorktrees
    case refreshWorktrees
    case ghosttyCommand(String)
    case openPullRequest(Worktree.ID)
    case markPullRequestReady(Worktree.ID)
    case mergePullRequest(Worktree.ID)
    case closePullRequest(Worktree.ID)
    case copyFailingJobURL(Worktree.ID)
    case copyCiFailureLogs(Worktree.ID)
    case rerunFailedJobs(Worktree.ID)
    case openFailingCheckDetails(Worktree.ID)
    case runScript(ScriptDefinition)
    case stopScript(UUID, name: String)
    #if DEBUG
      case debugTestToast(RepositoriesFeature.StatusToast)
    #endif
  }

  /// Which section the item belongs to in the palette: commands that act on the current
  /// window/worktree (terminal actions, scripts, this worktree's PR / rename / remove / archive)
  /// are grouped ABOVE the app-wide/general commands (open repo, settings, new worktree, updates,
  /// navigate to another worktree). Distinct from the legacy `isGlobal`, which conflates "shown
  /// regardless of selection" with scope.
  enum Scope: Equatable {
    case worktree
    case general
  }

  var scope: Scope {
    switch kind {
    case .ghosttyCommand, .runScript, .stopScript, .renameBranch, .removeWorktree, .archiveWorktree,
      .openPullRequest, .markPullRequestReady, .mergePullRequest, .closePullRequest,
      .copyFailingJobURL, .copyCiFailureLogs, .rerunFailedJobs, .openFailingCheckDetails:
      .worktree
    case .checkForUpdates, .openRepository, .addRemoteRepository, .openSettings, .newWorktree,
      .viewArchivedWorktrees, .refreshWorktrees, .worktreeSelect:
      .general
    #if DEBUG
      case .debugTestToast:
        .general
    #endif
    }
  }

  /// The raw Ghostty terminal-binding firehose (every bound terminal action). Kept out of the
  /// empty-query default view (there are many) but included when the user searches.
  var isRawTerminalCommand: Bool {
    if case .ghosttyCommand = kind { true } else { false }
  }

  var isGlobal: Bool {
    switch kind {
    case .checkForUpdates, .openRepository, .addRemoteRepository, .openSettings, .newWorktree,
      .viewArchivedWorktrees, .refreshWorktrees:
      true
    case .ghosttyCommand:
      false
    case .openPullRequest,
      .markPullRequestReady,
      .mergePullRequest,
      .closePullRequest,
      .copyFailingJobURL,
      .copyCiFailureLogs,
      .rerunFailedJobs,
      .openFailingCheckDetails:
      true
    case .worktreeSelect, .removeWorktree, .archiveWorktree:
      false
    case .renameBranch:
      true
    case .runScript, .stopScript:
      true
    #if DEBUG
      case .debugTestToast:
        true
    #endif
    }
  }

  var isRootAction: Bool {
    switch kind {
    case .checkForUpdates, .openRepository, .addRemoteRepository, .openSettings, .newWorktree,
      .viewArchivedWorktrees, .refreshWorktrees:
      true
    case .ghosttyCommand:
      false
    case .openPullRequest,
      .markPullRequestReady,
      .mergePullRequest,
      .closePullRequest,
      .copyFailingJobURL,
      .copyCiFailureLogs,
      .rerunFailedJobs,
      .openFailingCheckDetails,
      .worktreeSelect,
      .removeWorktree,
      .archiveWorktree,
      .renameBranch:
      false
    case .runScript, .stopScript:
      false
    #if DEBUG
      case .debugTestToast:
        false
    #endif
    }
  }

  var appShortcut: AppShortcut? {
    switch kind {
    case .checkForUpdates: AppShortcuts.checkForUpdates
    case .openRepository: AppShortcuts.openRepository
    case .openSettings: AppShortcuts.openSettings
    case .newWorktree: AppShortcuts.newWorktree
    case .viewArchivedWorktrees: AppShortcuts.archivedWorktrees
    case .refreshWorktrees: AppShortcuts.refreshWorktrees
    case .ghosttyCommand: nil
    case .openPullRequest: AppShortcuts.openPullRequest
    case .addRemoteRepository,
      .markPullRequestReady,
      .mergePullRequest,
      .closePullRequest,
      .copyFailingJobURL,
      .copyCiFailureLogs,
      .rerunFailedJobs,
      .openFailingCheckDetails,
      .worktreeSelect,
      .removeWorktree,
      .archiveWorktree,
      .renameBranch,
      .stopScript:
      nil
    case .runScript(let definition):
      definition.kind == .run ? AppShortcuts.runScript : nil
    #if DEBUG
      case .debugTestToast:
        nil
    #endif
    }
  }

  var appShortcutLabel: String? {
    effectiveAppShortcut?.display
  }

  var appShortcutSymbols: [String]? {
    effectiveAppShortcut?.displaySymbols
  }

  private var effectiveAppShortcut: AppShortcut? {
    guard let shortcut = appShortcut else { return nil }
    @Shared(.settingsFile) var settingsFile
    return shortcut.effective(from: settingsFile.global.shortcutOverrides)
  }
}
