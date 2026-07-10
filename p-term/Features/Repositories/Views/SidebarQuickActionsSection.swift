import AppKit
import ComposableArchitecture
import OrderedCollections
import PTermSettingsShared
import Sharing
import SwiftUI

// Claude Cowork chrome: "+ New" then quiet nav rows — monochrome, no glass.
struct SidebarQuickActionsSection: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  let selectedWorktreeIDs: Set<Worktree.ID>
  let openRepositoryShortcut: String?

  var body: some View {
    Section {
      Button {
        store.send(.createRandomWorktree)
      } label: {
        SidebarComposerLabel(title: "New", systemImage: "plus")
      }
      .buttonStyle(.plain)
      .help("Create a new terminal workspace")

      Menu {
        Button {
          store.send(.setOpenPanelPresented(true))
        } label: {
          Label("Local folder…", systemImage: "laptopcomputer")
        }
        .help("Open a local workspace or folder (\(openRepositoryShortcut ?? "none"))")

        Button {
          store.send(.requestAddRemoteRepository)
        } label: {
          Label("SSH folder…", systemImage: "network")
        }
        .help("Open a folder on an SSH host")

        Divider()

        Button {
          store.send(.requestCloneRepository)
        } label: {
          Label("Clone repository…", systemImage: "square.and.arrow.down.on.square")
        }
        .help("Clone a remote repository into a local folder")

        Divider()

        Button {
          store.send(.refreshWorktrees)
        } label: {
          Label("Reload workspaces", systemImage: "arrow.clockwise")
        }

        if selectedWorktreeIDs.count == 1, let worktreeID = selectedWorktreeIDs.first {
          Button {
            store.send(.revealHoistedWorktreeInSidebar(worktreeID))
          } label: {
            Label("Reveal selected", systemImage: "scope")
          }
        }
      } label: {
        SidebarComposerLabel(title: "Open", systemImage: "folder")
      }
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .help("Open a local folder, SSH folder, or clone")

      if let customizationTarget {
        Button {
          switch customizationTarget {
          case .repository(let id):
            store.send(.requestCustomizeRepository(id))
          case .worktree(let worktreeID, let repositoryID):
            store.send(.requestCustomizeWorktree(worktreeID, repositoryID))
          }
        } label: {
          SidebarComposerLabel(title: "Customize", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.plain)
        .help("Customize the selected workspace")
      }
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

private struct SidebarComposerLabel: View {
  let title: String
  let systemImage: String

  var body: some View {
    Label {
      Text(title)
        .font(AppTypography.body)
        .foregroundStyle(.primary)
        .lineLimit(1)
    } icon: {
      Image(systemName: systemImage)
        .font(AppTypography.body.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
        .symbolRenderingMode(.hierarchical)
    }
    .labelStyle(.verticallyCentered)
    .frame(maxWidth: .infinity, minHeight: SidebarNestLayout.rowMinHeight, alignment: .leading)
    .contentShape(.interaction, .rect)
    .listRowInsets(.leading, 0)
    .listRowInsets(.trailing, SidebarNestLayout.trailingInset)
    .listRowInsets(.vertical, SidebarNestLayout.rowVerticalInset)
    .typeSelectEquivalent("")
  }
}

/// Shared with Prjct panel CTAs.
struct SidebarPrimaryActionRow: View {
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

struct SidebarPrimaryActionLabel: View {
  let title: String
  let systemImage: String
  var isProminent = false

  var body: some View {
    Label {
      Text(title)
        .font(AppTypography.body)
        .lineLimit(1)
    } icon: {
      Image(systemName: systemImage)
        .font(AppTypography.body.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
        .symbolRenderingMode(.hierarchical)
    }
    .labelStyle(.verticallyCentered)
    .foregroundStyle(.primary)
    .frame(maxWidth: .infinity, minHeight: SidebarNestLayout.rowMinHeight, alignment: .leading)
    .contentShape(.interaction, .rect)
    .listRowInsets(.leading, 0)
    .listRowInsets(.trailing, SidebarNestLayout.trailingInset)
    .listRowInsets(.vertical, SidebarNestLayout.rowVerticalInset)
    .typeSelectEquivalent("")
  }
}
