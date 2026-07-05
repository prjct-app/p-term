import PTermSettingsShared
import SwiftUI

/// Dynamic-Island-style capsule showing `ToolbarStatusSignal.resolve(_:)`'s
/// highest-priority signal for the focused worktree's active terminal tab.
/// Click expands `ToolbarStatusIslandPopoverView` with full detail + the
/// auto/pinned mode picker.
struct ToolbarStatusIslandView: View {
  let inputs: ToolbarStatusSignal.Inputs
  let onSetMode: (ToolbarStatusWidgetMode) -> Void
  let onOpenCommandPalette: () -> Void

  @State private var isPresented = false

  private var signal: ToolbarStatusSignal { ToolbarStatusSignal.resolve(inputs) }
  private var opensCommandPalette: Bool {
    switch signal {
    case .time: true
    default: false
    }
  }

  var body: some View {
    ToolbarControlButton(
      primaryAction: {
        if opensCommandPalette {
          isPresented = false
          onOpenCommandPalette()
        } else {
          isPresented = true
        }
      },
      width: layout(for: signal)
    ) {
      icon(for: signal)
        .contentTransition(.symbolEffect(.replace))
    } label: {
      text(for: signal)
    } menu: {
      ForEach(ToolbarStatusWidgetMode.allCases, id: \.self) { mode in
        Button {
          onSetMode(mode)
        } label: {
          if mode == inputs.pinnedMode {
            Label(mode.label, systemImage: "checkmark")
          } else {
            Text(mode.label)
          }
        }
      }
    }
    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: signal.transitionToken)
    .popover(isPresented: $isPresented) {
      ToolbarStatusIslandPopoverView(
        inputs: inputs, currentMode: inputs.pinnedMode, onSetMode: onSetMode
      )
      .inheritSystemColorScheme()
    }
    .help(helpText(for: signal))
  }

  @ViewBuilder
  private func icon(for signal: ToolbarStatusSignal) -> some View {
    switch signal {
    case .agentAwaitingInput:
      Image(systemName: "exclamationmark.bubble.fill")
        .foregroundStyle(.orange)
    case .agentWorking:
      Image(systemName: "sparkles")
        .foregroundStyle(.tint)
    case .runningScript:
      Image(systemName: "terminal.fill")
        .foregroundStyle(.tint)
    case .pullRequest(let model):
      Image(systemName: "arrow.triangle.pull")
        .foregroundStyle(model.badgeColor)
    case .branch:
      Image(systemName: "arrow.triangle.branch")
        .foregroundStyle(.secondary)
    case .time:
      TimelineView(.everyMinute) { context in
        let style = ToolbarTimeStyle.style(
          for: Calendar.current.component(.hour, from: context.date))
        Image(systemName: style.icon)
          .foregroundStyle(style.color)
      }
    }
  }

  @ViewBuilder
  private func text(for signal: ToolbarStatusSignal) -> some View {
    switch signal {
    case .agentAwaitingInput(let agent):
      Text(agentLabel(agent, status: "needs input"))
        .foregroundStyle(.primary)
    case .agentWorking(let agent):
      Text(agentLabel(agent, status: "working"))
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

  /// "Codex · main — working": which agent, on which branch, doing what — the
  /// dev's core "what am I looking at" line. Branch is dropped when unknown.
  private func agentLabel(_ agent: SkillAgent, status: String) -> String {
    let branch = inputs.branchName.trimmingCharacters(in: .whitespacesAndNewlines)
    let head = branch.isEmpty ? agent.displayName : "\(agent.displayName) · \(branch)"
    return "\(head) — \(status)"
  }

  private func layout(for signal: ToolbarStatusSignal) -> ToolbarControlWidth {
    switch signal {
    case .time:
      ToolbarControlWidth(min: 300, ideal: 340, max: 380)
    case .agentAwaitingInput, .agentWorking:
      ToolbarControlWidth(min: 160, ideal: 200, max: 280)
    case .runningScript, .pullRequest:
      ToolbarControlWidth(min: 180, ideal: 240, max: 340)
    case .branch:
      ToolbarControlWidth(min: 100, ideal: 140, max: 240)
    }
  }

  private func helpText(for signal: ToolbarStatusSignal) -> String {
    switch signal {
    case .agentAwaitingInput(let agent):
      "\(agent.rawValue) is waiting for input. Click for details."
    case .agentWorking(let agent): "\(agent.rawValue) is working. Click for details."
    case .runningScript: "A script is running in this tab. Click for details."
    case .pullRequest(let model): "Pull request #\(model.number). Click for details."
    case .branch(let name): "Branch \(name). Click for details."
    case .time: "Open Command Palette (⌘P)."
    }
  }
}
