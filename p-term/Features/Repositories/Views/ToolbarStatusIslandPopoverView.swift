import PTermSettingsShared
import SwiftUI

/// Full detail behind the toolbar status island: branch, PR summary, the
/// active tab's script/agent status (labeled with the tab's own title so
/// it's unambiguous which tab this refers to), and the auto/pinned mode picker.
struct ToolbarStatusIslandPopoverView: View {
  let inputs: ToolbarStatusSignal.Inputs
  let currentMode: ToolbarStatusWidgetMode
  let onSetMode: (ToolbarStatusWidgetMode) -> Void

  @Environment(\.openURL) private var openURL

  private var pullRequestModel: PullRequestStatusModel? {
    PullRequestStatusModel(pullRequest: inputs.pullRequest)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !inputs.branchName.isEmpty {
        Label(inputs.branchName, systemImage: "arrow.triangle.branch")
          .monospaced()
          .font(AppTypography.callout)
      }

      if let pullRequestModel {
        Button {
          if let url = URL(string: pullRequestModel.pullRequest.url) {
            openURL(url)
          }
        } label: {
          HStack(spacing: 6) {
            PullRequestBadgeView(text: pullRequestModel.badgeText, color: pullRequestModel.badgeColor)
            Text(pullRequestModel.detailText ?? pullRequestModel.title)
              .lineLimit(2)
          }
        }
        .buttonStyle(.plain)
        .help("Open pull request #\(pullRequestModel.number) on GitHub.")
      }

      Divider()

      VStack(alignment: .leading, spacing: 4) {
        Label(inputs.activeTabTitle.isEmpty ? "This tab" : inputs.activeTabTitle, systemImage: "terminal")
          .font(AppTypography.callout)
        if inputs.activeTabIsRunningScript {
          Text("Running a script.")
            .foregroundStyle(.secondary)
        }
        if inputs.activeTabAgents.isEmpty {
          if !inputs.activeTabIsRunningScript {
            Text("No agent activity.")
              .foregroundStyle(.secondary)
          }
        } else {
          ForEach(inputs.activeTabAgents, id: \.self) { instance in
            Text("\(instance.agent.rawValue): \(activityLabel(instance.activity))")
              .foregroundStyle(.secondary)
          }
        }
      }
      .font(AppTypography.footnote)

      Divider()

      Picker("Show", selection: Binding(get: { currentMode }, set: onSetMode)) {
        ForEach(ToolbarStatusWidgetMode.allCases, id: \.self) { mode in
          Text(mode.label).tag(mode)
        }
      }
      .pickerStyle(.menu)
      .help("Choose which signal the toolbar status island shows.")
    }
    .padding(12)
    .frame(minWidth: 260, maxWidth: 360)
  }

  private func activityLabel(_ activity: AgentPresenceFeature.Activity) -> String {
    switch activity {
    case .awaitingInput: "needs input"
    case .busy: "working"
    case .idle: "idle"
    }
  }
}
