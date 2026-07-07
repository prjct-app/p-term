import AppKit
import ComposableArchitecture
import OrderedCollections
import PTermSettingsShared
import Sharing
import SwiftUI

// Collapsible Project (repo-group) header (extracted from SidebarListView).
struct SidebarProjectHeaderView: View {
  let projectID: ProjectID
  let name: String
  let color: RepositoryColor?
  let collapsed: Bool
  let memberCount: Int
  @Bindable var store: StoreOf<RepositoriesFeature>

  @State private var isRenaming = false
  @State private var draftTitle = ""

  var body: some View {
    rowContent
      .labelStyle(.verticallyCentered)
      .listRowInsets(.leading, 0)
      .listRowInsets(.trailing, 4)
      .listRowInsets(.vertical, 6)
      .typeSelectEquivalent("")
      .moveDisabled(true)
      .contextMenu {
        Button("Rename Project…") { startRenaming() }
        Menu("Project Color") {
          Button("Default") { store.send(.setProjectColor(projectID, nil)) }
          Divider()
          ForEach(RepositoryColor.predefined, id: \.self) { swatch in
            Button {
              store.send(.setProjectColor(projectID, swatch))
            } label: {
              if swatch == color {
                Label(swatch.displayName, systemImage: "checkmark")
              } else {
                Text(swatch.displayName)
              }
            }
          }
        }
        Divider()
        Button("Delete Project", role: .destructive) {
          store.send(.deleteProject(projectID))
        }
      }
      .accessibilityLabel("Project \(name), \(memberCount) workspaces")
  }

  @ViewBuilder private var rowContent: some View {
    if isRenaming {
      projectLabel(renaming: true)
    } else {
      projectLabel(renaming: false)
        .contentShape(.rect)
        .onTapGesture(count: 2) { startRenaming() }
        .onTapGesture { store.send(.toggleProjectCollapsed(projectID)) }
        .accessibilityAddTraits(.isButton)
    }
  }

  private func projectLabel(renaming: Bool) -> some View {
    Label {
      HStack(spacing: 8) {
        if renaming {
          SidebarInlineRenameField(
            text: $draftTitle,
            font: AppTypography.caption.weight(.semibold),
            accessibilityLabel: "Rename project",
            onCommit: commitRename,
            onCancel: { isRenaming = false }
          )
        } else {
          Text(name.uppercased())
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(color?.color ?? .secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        Text("\(memberCount)")
          .font(AppTypography.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: collapsed ? "chevron.right" : "chevron.down")
        .font(AppTypography.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    }
  }

  private func startRenaming() {
    draftTitle = name
    isRenaming = true
  }

  private func commitRename() {
    guard isRenaming else { return }
    isRenaming = false
    let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != name else { return }
    store.send(.renameProject(projectID, title: trimmed))
  }
}
