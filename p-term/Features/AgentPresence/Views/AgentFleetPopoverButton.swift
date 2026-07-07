import PTermSettingsShared
import SwiftUI

/// Toolbar entry point for the cross-project agent fleet: every running
/// agent across every worktree, live. Sibling of `ToolbarNotificationsPopoverButton`
/// — same hover/pin/dismiss choreography, different payload.
struct AgentFleetPopoverButton: View {
  let groups: [AgentFleetRepositoryGroup]
  let onSelect: (Worktree.ID, UUID) -> Void
  @State private var isPresented = false
  @State private var isPinnedOpen = false
  @State private var isHoveringButton = false
  @State private var isHoveringPopover = false
  @State private var closeTask: Task<Void, Never>?

  private var busyCount: Int { groups.reduce(0) { $0 + $1.busyCount } }
  private var awaitingInputCount: Int { groups.reduce(0) { $0 + $1.awaitingInputCount } }

  var body: some View {
    ToolbarGlassCapsuleButton {
      togglePresentation()
    } label: {
      HStack(spacing: AppChromeMetrics.Toolbar.contentSpacing) {
        Image(systemName: awaitingInputCount > 0 ? "person.2.badge.gearshape.fill" : "person.2.fill")
          .foregroundStyle(awaitingInputCount > 0 ? .orange : .secondary)
          .frame(width: AppChromeMetrics.Toolbar.iconSize, height: AppChromeMetrics.Toolbar.iconSize)
          .accessibilityHidden(true)
        let total = busyCount + awaitingInputCount
        if total > 0 {
          Text(total, format: .number)
            .font(AppTypography.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
    .help("Agents. Hover or click to show every running agent across your projects.")
    .accessibilityLabel("Agent fleet")
    .onHover { hovering in
      isHoveringButton = hovering
      updatePresentation()
    }
    .popover(isPresented: $isPresented) {
      AgentFleetPopoverView(
        groups: groups,
        onSelect: { worktreeID, surfaceID in
          onSelect(worktreeID, surfaceID)
          closePopover()
        }
      )
      .frame(minWidth: 320, maxWidth: 520, maxHeight: 440)
      .onHover { hovering in
        isHoveringPopover = hovering
        updatePresentation()
      }
      .onDisappear {
        isHoveringPopover = false
        isPinnedOpen = false
      }
      .inheritSystemColorScheme()
    }
    .onChange(of: groups) { _, newValue in
      if newValue.isEmpty {
        closePopover()
      }
    }
    .onDisappear {
      closeTask?.cancel()
    }
  }

  private func togglePresentation() {
    if isPinnedOpen {
      closePopover()
      return
    }
    closeTask?.cancel()
    isPinnedOpen = true
    isPresented = true
  }

  private func updatePresentation() {
    if isPinnedOpen || isHoveringButton || isHoveringPopover {
      closeTask?.cancel()
      isPresented = true
      return
    }
    closeTask?.cancel()
    closeTask = Task { @MainActor in
      try? await ContinuousClock().sleep(for: .milliseconds(150))
      if !Task.isCancelled {
        isPresented = false
      }
    }
  }

  private func closePopover() {
    closeTask?.cancel()
    isPinnedOpen = false
    isPresented = false
  }
}

/// Not `private` — also reused as the content of a native "Agent Fleet" split
/// pane (see `AgentFleetPaneView`), not just this popover.
struct AgentFleetPopoverView: View {
  let groups: [AgentFleetRepositoryGroup]
  let onSelect: (Worktree.ID, UUID) -> Void

  var body: some View {
    let agentCount = groups.reduce(0) { $0 + $1.worktrees.reduce(0) { $0 + $1.agents.count } }
    let agentLabel = agentCount == 1 ? "agent" : "agents"

    ScrollView {
      VStack(alignment: .leading, spacing: AppChromeMetrics.Popover.sectionSpacing) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Agents")
            .font(AppTypography.headline)
          Text("\(agentCount) \(agentLabel) running")
            .font(AppTypography.subheadline)
            .foregroundStyle(.secondary)
        }

        ForEach(groups) { repository in
          VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(repository.name)
              .font(AppTypography.subheadline)
            ForEach(repository.worktrees) { worktree in
              VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: AppChromeMetrics.Popover.rowSpacing) {
                  Text(worktree.name)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                  if !worktree.branchName.isEmpty {
                    Text(worktree.branchName)
                      .font(AppTypography.caption)
                      .foregroundStyle(.tertiary)
                  }
                }
                ForEach(worktree.agents, id: \.surfaceID) { instance in
                  Button {
                    onSelect(worktree.id, instance.surfaceID)
                  } label: {
                    HStack(spacing: AppChromeMetrics.Popover.rowSpacing) {
                      AgentBadgeView(agent: instance.agent, size: 16, awaitingInput: instance.awaitingInput)
                      Text(instance.agent.displayName)
                        .font(AppTypography.body)
                      Spacer()
                      Text(activityLabel(for: instance.activity))
                        .font(AppTypography.caption)
                        .foregroundStyle(instance.awaitingInput ? .orange : .secondary)
                    }
                  }
                  .buttonStyle(.plain)
                  .help("Jump to \(worktree.name)")
                }
              }
            }
          }
        }
      }
      .padding()
    }
  }

  private func activityLabel(for activity: AgentPresenceFeature.Activity) -> String {
    switch activity {
    case .awaitingInput: "Needs input"
    case .busy: "Working"
    case .idle: "Idle"
    }
  }
}
