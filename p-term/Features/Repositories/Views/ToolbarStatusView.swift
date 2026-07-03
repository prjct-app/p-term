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
        HStack(spacing: AppChromeMetrics.Toolbar.contentSpacing) {
          ProgressView()
            .controlSize(.small)
            .frame(width: AppChromeMetrics.Toolbar.iconSize, height: AppChromeMetrics.Toolbar.iconSize)
          Text(message)
            .font(AppTypography.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppChromeMetrics.Toolbar.horizontalPadding)
        .padding(.vertical, AppChromeMetrics.Toolbar.verticalPadding)
        .frame(minHeight: AppChromeMetrics.Toolbar.controlHeight)
        .transition(.opacity)
      case .success(let message):
        HStack(spacing: AppChromeMetrics.Toolbar.contentSpacing) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .frame(width: AppChromeMetrics.Toolbar.iconSize, height: AppChromeMetrics.Toolbar.iconSize)
            .accessibilityHidden(true)
          Text(message)
            .font(AppTypography.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppChromeMetrics.Toolbar.horizontalPadding)
        .padding(.vertical, AppChromeMetrics.Toolbar.verticalPadding)
        .frame(minHeight: AppChromeMetrics.Toolbar.controlHeight)
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
