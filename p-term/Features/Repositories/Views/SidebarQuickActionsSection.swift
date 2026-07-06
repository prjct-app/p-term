import AppKit
import ComposableArchitecture
import OrderedCollections
import PTermSettingsShared
import Sharing
import SwiftUI

// Quick actions block at the top of the sidebar (extracted from SidebarListView).
struct SidebarQuickActionsSection: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  let selectedWorktreeIDs: Set<Worktree.ID>
  let openRepositoryShortcut: String?

  var body: some View {
    Section {
      SidebarPrimaryActionRow(
        title: "New session",
        systemImage: "plus",
        isProminent: true
      ) {
        store.send(.createRandomWorktree)
      }
      .help("Start a new terminal session")

      Menu {
        Button {
          store.send(.setOpenPanelPresented(true))
        } label: {
          Label("Local folder…", systemImage: "laptopcomputer")
        }
        .help("Open a local repository or folder (\(openRepositoryShortcut ?? "none"))")

        Button {
          store.send(.requestAddRemoteRepository)
        } label: {
          Label("SSH folder…", systemImage: "wifi")
        }
        .help("Open a folder on an SSH host")

        Divider()

        Button {
          store.send(.requestCloneRepository)
        } label: {
          Label("Clone repository…", systemImage: "square.and.arrow.down.on.square")
        }
        .help("Clone a remote repository into a local folder")
      } label: {
        SidebarPrimaryActionLabel(title: "Open source", systemImage: "externaldrive.connected.to.line.below")
      }
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .help("Open a local folder, SSH folder, or clone")

      if let customizationTarget {
        SidebarPrimaryActionRow(title: "Customize", systemImage: "slider.horizontal.3") {
          switch customizationTarget {
          case .repository(let id):
            store.send(.requestCustomizeRepository(id))
          case .worktree(let worktreeID, let repositoryID):
            store.send(.requestCustomizeWorktree(worktreeID, repositoryID))
          }
        }
        .help("Customize the selected session")
      }

      Menu {
        Button {
          store.send(.refreshWorktrees)
        } label: {
          Label("Reload sessions", systemImage: "arrow.clockwise")
        }
        if selectedWorktreeIDs.count == 1, let worktreeID = selectedWorktreeIDs.first {
          Button {
            store.send(.revealHoistedWorktreeInSidebar(worktreeID))
          } label: {
            Label("Reveal selected", systemImage: "scope")
          }
        }
      } label: {
        SidebarPrimaryActionLabel(title: "More", systemImage: "chevron.down")
      }
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .help("More session actions")
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

private struct SidebarPrimaryActionRow: View {
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

private struct SidebarPrimaryActionLabel: View {
  let title: String
  let systemImage: String
  var isProminent = false

  var body: some View {
    Label {
      Text(title)
        .font(AppTypography.body.weight(isProminent ? .semibold : .regular))
        .lineLimit(1)
    } icon: {
      Image(systemName: systemImage)
        .font(AppTypography.body.weight(.medium))
        .foregroundStyle(isProminent ? .primary : .secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    }
    .labelStyle(.verticallyCentered)
    .foregroundStyle(.primary)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      if isProminent {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(.quaternary)
      }
    }
    .contentShape(.interaction, .rect)
    .listRowInsets(.leading, 0)
    .listRowInsets(.trailing, 4)
    .listRowInsets(.vertical, 2)
    .typeSelectEquivalent("")
  }
}
