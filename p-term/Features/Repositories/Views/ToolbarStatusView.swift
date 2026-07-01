import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

struct ToolbarStatusView: View {
  let toast: RepositoriesFeature.StatusToast?
  let toolbarState: WorktreeDetailView.WorktreeToolbarState
  let worktreeID: Worktree.ID
  let terminalManager: WorktreeTerminalManager
  let terminalsStore: StoreOf<TerminalsFeature>?
  let onSetMode: (ToolbarStatusWidgetMode) -> Void

  var body: some View {
    Group {
      switch toast {
      case .inProgress(let message):
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)
          Text(message)
            .font(AppTypography.footnote)
            .foregroundStyle(.secondary)
        }
        .transition(.opacity)
      case .success(let message):
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .accessibilityHidden(true)
          Text(message)
            .font(AppTypography.footnote)
            .foregroundStyle(.secondary)
        }
        .transition(.opacity)
      case nil:
        WorktreeDetailView.ToolbarStatusIslandHost(
          toolbarState: toolbarState,
          worktreeID: worktreeID,
          terminalManager: terminalManager,
          terminalsStore: terminalsStore,
          onSetMode: onSetMode
        )
        .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: toast)
  }
}

/// Sun/moon-by-hour styling, reused by the island's `.time` fallback case.
struct ToolbarTimeStyle {
  let icon: String
  let color: Color

  static func style(for hour: Int) -> ToolbarTimeStyle {
    switch hour {
    case 6..<12:
      ToolbarTimeStyle(icon: "sunrise.fill", color: .orange)
    case 12..<17:
      ToolbarTimeStyle(icon: "sun.max.fill", color: .yellow)
    case 17..<21:
      ToolbarTimeStyle(icon: "sunset.fill", color: .pink)
    default:
      ToolbarTimeStyle(icon: "moon.stars.fill", color: .indigo)
    }
  }
}
