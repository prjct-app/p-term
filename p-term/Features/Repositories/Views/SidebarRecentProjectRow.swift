import AppKit
import ComposableArchitecture
import OrderedCollections
import PTermSettingsShared
import Sharing
import SwiftUI

// Recents row for a repository/folder with no open terminals
// (extracted from SidebarListView).
struct SidebarRecentProjectRow: View {
  let repositoryID: Repository.ID
  /// Snapshot from the render plan (`SidebarStructure.RepositoryDisplay`) so
  /// this row renders without reading `repositories` live — a live read made
  /// any worktree mutation anywhere re-run every section body.
  let display: SidebarStructure.RepositoryDisplay
  let rowIDs: [SidebarItemID]
  @Bindable var store: StoreOf<RepositoriesFeature>

  @State private var isRenaming = false
  @State private var draftTitle = ""

  private var displayName: String {
    Repository.sidebarDisplayName(custom: display.customTitle, fallback: display.name)
  }

  private var subtitle: String? {
    display.host?.displayAuthority
  }

  private var projects: [SidebarProject] {
    Array(store.state.sidebar.projects.values)
  }

  private var currentProjectID: ProjectID? {
    store.state.sidebar.projectID(containing: repositoryID)
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
          store.send(.createProject(name: "New Project", repositoryIDs: [repositoryID]))
        }
        if !projects.isEmpty {
          Menu("Add to Project") {
            ForEach(projects) { project in
              Button {
                store.send(.addRepositoryToProject(repositoryID, project.id))
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
            store.send(.removeRepositoryFromProject(repositoryID))
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
            SidebarInlineRenameField(
              text: $draftTitle,
              accessibilityLabel: "Rename workspace",
              onCommit: commitRename,
              onCancel: { isRenaming = false }
            )
          } else {
            Text(displayName)
              .font(AppTypography.body)
              .foregroundStyle(display.color?.color ?? .primary)
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
      Image(systemName: display.host == nil ? "folder" : "wifi")
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
    if display.isGitRepository {
      store.send(.commitRepositorySectionTitle(repositoryID, title: trimmed))
    } else if let rowID = rowIDs.first {
      store.send(.commitInlineTitle(worktreeID: rowID, repositoryID: repositoryID, title: trimmed))
    }
  }
}

/// Collapsible header for a user-created Project grouping several repositories.
/// Single click toggles collapse; double click renames inline. Context menu
/// renames or deletes (delete ungroups its repos, never deletes them).
