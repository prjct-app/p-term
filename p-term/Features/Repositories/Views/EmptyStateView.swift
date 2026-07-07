import ComposableArchitecture
import PTermSettingsShared
import Sharing
import SwiftUI

struct EmptyStateView: View {
  let store: StoreOf<RepositoriesFeature>
  @Shared(.settingsFile) private var settingsFile

  var body: some View {
    let openRepo = AppShortcuts.openRepository.effective(from: settingsFile.global.shortcutOverrides)

    VStack(spacing: 12) {
      Image(systemName: "tray")
        .font(AppTypography.title)
        .imageScale(.large)
        .accessibilityHidden(true)
        .foregroundStyle(.secondary)
      VStack(spacing: 4) {
        Text("Open a workspace or folder")
          .font(AppTypography.title3)
        Text(
          "Press \(openRepo?.display ?? AppShortcuts.openRepository.display) "
            + "or click Open Workspace or Folder to choose one."
        )
        .font(AppTypography.subheadline)
        .foregroundStyle(.secondary)
      }
      Button("Open Workspace or Folder...") {
        store.send(.setOpenPanelPresented(true))
      }
      .appKeyboardShortcut(openRepo)
      .help("Open Workspace or Folder (\(openRepo?.display ?? "none"))")
      Button("Add Remote Workspace…") {
        store.send(.requestAddRemoteRepository)
      }
      .buttonStyle(.link)
      .help("Add a workspace or folder on an SSH host")
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
