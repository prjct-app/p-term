import AppKit
import PTermSettingsShared
import SwiftUI

/// Shared per-pane header — used by BOTH tiled (`TerminalSplitTreeView.LeafView`
/// / `NativePaneLeafView`) and paper (`PaperLayoutView`) panes so the same
/// actions are available regardless of which layout mode a tab is in. Drag
/// reordering works differently in each mode (tiled panes drag/drop onto each
/// other via `NSItemProvider`; paper columns drag via a plain `DragGesture`
/// with tracked frames), so the drag affordance itself is a slot the caller
/// fills in rather than something this view knows how to do.
struct PaneHeaderView<DragHandle: View>: View {
  let title: String
  let icon: PaneHeaderIcon
  let isActive: Bool
  let onClose: () -> Void
  /// `nil` hides "Git Diff" from the menu (no worktree context to build the
  /// attached panel from — shouldn't happen in practice, but a pane leaf
  /// created via some future path might not have one).
  let onToggleGitDiffPanel: (() -> Void)?
  @ViewBuilder let dragHandle: () -> DragHandle

  @State private var isPressingClose = false

  static var height: CGFloat { 36 }
  private let actionSize: CGFloat = 22
  private let iconSize: CGFloat = 12

  var body: some View {
    HStack(spacing: AppDesign.Spacing.rowContent) {
      dragHandle()
        .font(.system(size: iconSize, weight: .regular))

      PaneHeaderIconView(icon: icon, size: iconSize)

      Text(title)
        .font(.body)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Spacer(minLength: 0)

      if let onToggleGitDiffPanel {
        Button {
          onToggleGitDiffPanel()
        } label: {
          Image(systemName: "arrow.left.arrow.right")
        }
        .buttonStyle(.plain)
        .font(.system(size: iconSize, weight: .regular))
        .foregroundStyle(.primary.opacity(0.82))
        .frame(width: actionSize, height: actionSize)
        .contentShape(.rect)
        .help("Toggle Git Diff")
        .accessibilityLabel("Toggle Git Diff")
      }

      Button("Close Pane", systemImage: "xmark") {
        onClose()
      }
      .labelStyle(.iconOnly)
      .buttonStyle(TerminalPressTrackingButtonStyle(isPressed: $isPressingClose))
      .font(.system(size: iconSize, weight: .regular))
      .foregroundStyle(.primary.opacity(0.82))
      .frame(width: actionSize, height: actionSize)
      .background(Color.primary.opacity(isPressingClose ? 0.12 : 0), in: .circle)
      .contentShape(.rect)
      .help("Close Pane")
      .accessibilityLabel("Close Pane")
    }
    .padding(.horizontal, AppDesign.Padding.rowHorizontal)
    .padding(.vertical, AppDesign.Padding.rowVertical)
    .frame(height: Self.height)
    .frame(maxWidth: .infinity)
    .background {
      // Active pane gets a slightly stronger glass wash so focus is obvious
      // without a heavy border (pairs with pane chrome stroke).
      Rectangle()
        .fill(.ultraThinMaterial.opacity(isActive ? 0.85 : 0.55))
    }
    .contentShape(.rect)
  }
}

enum PaneHeaderIcon: Equatable {
  case shell
  case agent(SkillAgent, awaitingInput: Bool)
  case detectedAgentFallback
  case native(systemName: String)

  static func resolve(
    for surfaceID: UUID,
    surfaceTitle: String?,
    tabState: TerminalTabFeature.State?
  ) -> PaneHeaderIcon {
    if let agent = tabState?.agents.first(where: { $0.surfaceID == surfaceID }) {
      return .agent(agent.agent, awaitingInput: agent.awaitingInput)
    }
    if let raw = surfaceTitle, let detected = KnownAgentCLI.match(inTitle: raw.lowercased()) {
      if let agent = detected.agent {
        return .agent(agent, awaitingInput: false)
      }
      return .detectedAgentFallback
    }
    return .shell
  }
}

private struct PaneHeaderIconView: View {
  let icon: PaneHeaderIcon
  let size: CGFloat

  var body: some View {
    Group {
      switch icon {
      case .shell:
        Image(systemName: "terminal")
          .font(.system(size: size, weight: .regular))
          .foregroundStyle(.secondary)
      case .agent(let agent, let awaitingInput):
        AgentBadgeView(agent: agent, size: size, awaitingInput: awaitingInput)
      case .detectedAgentFallback:
        Image(systemName: "sparkles")
          .font(.system(size: size, weight: .regular))
          .foregroundStyle(.secondary)
      case .native(let systemName):
        Image(systemName: systemName)
          .font(.system(size: size, weight: .regular))
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
