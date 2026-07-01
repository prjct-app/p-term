import PTermSettingsShared
import SwiftUI

/// Dynamic-Island-style capsule showing `ToolbarStatusSignal.resolve(_:)`'s
/// highest-priority signal for the focused worktree's active terminal tab.
/// Click expands `ToolbarStatusIslandPopoverView` with full detail + the
/// auto/pinned mode picker.
struct ToolbarStatusIslandView: View {
  let inputs: ToolbarStatusSignal.Inputs
  let onSetMode: (ToolbarStatusWidgetMode) -> Void

  @State private var isPresented = false

  private var signal: ToolbarStatusSignal { ToolbarStatusSignal.resolve(inputs) }

  var body: some View {
    GlassEffectContainer {
      Button {
        isPresented = true
      } label: {
        HStack(spacing: 6) {
          icon(for: signal)
            .contentTransition(.symbolEffect(.replace))
          text(for: signal)
            .lineLimit(1)
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
      }
      .buttonStyle(.plain)
      .glassEffect(.regular, in: .capsule)
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: signal.transitionToken)
    .popover(isPresented: $isPresented) {
      ToolbarStatusIslandPopoverView(inputs: inputs, currentMode: inputs.pinnedMode, onSetMode: onSetMode)
    }
    .help(helpText(for: signal))
  }

  @ViewBuilder
  private func icon(for signal: ToolbarStatusSignal) -> some View {
    switch signal {
    case .agentAwaitingInput:
      Image(systemName: "exclamationmark.bubble.fill")
        .foregroundStyle(.orange)
        .accessibilityHidden(true)
    case .agentWorking:
      Image(systemName: "sparkles")
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
    case .runningScript:
      Image(systemName: "terminal.fill")
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
    case .pullRequest(let model):
      Image(systemName: "arrow.triangle.pull")
        .foregroundStyle(model.badgeColor)
        .accessibilityHidden(true)
    case .branch:
      Image(systemName: "arrow.triangle.branch")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    case .time:
      TimelineView(.everyMinute) { context in
        let style = ToolbarTimeStyle.style(for: Calendar.current.component(.hour, from: context.date))
        Image(systemName: style.icon)
          .foregroundStyle(style.color)
          .accessibilityHidden(true)
      }
    }
  }

  @ViewBuilder
  private func text(for signal: ToolbarStatusSignal) -> some View {
    switch signal {
    case .agentAwaitingInput(let agent):
      Text("\(agent.rawValue) needs input")
        .foregroundStyle(.primary)
    case .agentWorking(let agent):
      Text("\(agent.rawValue) working")
        .foregroundStyle(.secondary)
    case .runningScript(let tabTitle):
      Text(tabTitle)
        .foregroundStyle(.secondary)
    case .pullRequest(let model):
      Text(model.detailText ?? model.title)
        .foregroundStyle(.secondary)
    case .branch(let name):
      Text(name)
        .monospaced()
        .foregroundStyle(.secondary)
    case .time:
      TimelineView(.everyMinute) { context in
        Text("\(context.date, format: .dateTime.hour().minute()) – Open Command Palette (⌘P)")
          .monospaced()
          .foregroundStyle(.secondary)
      }
    }
  }

  private func helpText(for signal: ToolbarStatusSignal) -> String {
    switch signal {
    case .agentAwaitingInput(let agent): "\(agent.rawValue) is waiting for input. Click for details."
    case .agentWorking(let agent): "\(agent.rawValue) is working. Click for details."
    case .runningScript: "A script is running in this tab. Click for details."
    case .pullRequest(let model): "Pull request #\(model.number). Click for details."
    case .branch(let name): "Branch \(name). Click for details."
    case .time: "Open Command Palette (⌘P)."
    }
  }
}
