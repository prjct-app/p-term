import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

struct PrjctPanelView: View {
  @Bindable var store: StoreOf<PrjctPanelFeature>
  let onRunCommand: (PrjctTerminalCommand) -> Void

  var body: some View {
    // Literally the left sidebar's own shape: a `List(.sidebar)` starting
    // immediately below the toolbar, no separate title bar above it — the
    // left sidebar has none, so a header here (tried once, reverted) was
    // extra chrome the reference doesn't have, not a fix for it.
    List {
      Section {
        SidebarPrimaryActionRow(
          title: "Refresh Dashboard",
          systemImage: "arrow.clockwise",
          isProminent: true
        ) {
          store.send(.refresh)
        }
        .disabled(store.isLoading)
        .help("Refresh prjct dashboard")
      }
      .moveDisabled(true)

      if store.snapshot.isEnabled {
        overviewSection
        actionsSection
        ForEach(store.snapshot.sections) { section in
          metricsSection(section)
        }
        workflowSection
        runsSection
      } else {
        Section {
          ContentUnavailableView {
            Label("No prjct project", systemImage: "folder.badge.questionmark")
          }
        }
      }
    }
    .listStyle(.sidebar)
    // `.listStyle(.sidebar)` alone only matches the real left sidebar's
    // background when the List sits in NavigationSplitView's actual
    // `sidebar:` slot. This panel lives in `detail:` instead, where the
    // List paints its own opaque background over the window's vibrancy —
    // same fix `ArchivedWorktreesDetailView` already uses for the same
    // reason (also a sidebar-styled List outside the sidebar slot).
    .scrollContentBackground(.hidden)
  }

  @ViewBuilder
  private var overviewSection: some View {
    let config = store.snapshot.config
    if config?.projectID != nil || config?.persona != nil || store.snapshot.reviewRisk != nil
      || store.snapshot.delivery != nil
    {
      Section {
        if let projectID = config?.projectID {
          overviewRow("Project", projectID, icon: "folder")
        }
        if let persona = config?.persona {
          overviewRow("Persona", persona, icon: "person.crop.circle")
        }
        if let risk = store.snapshot.reviewRisk {
          overviewRow("Review risk", risk, icon: "exclamationmark.triangle")
        }
        if let delivery = store.snapshot.delivery {
          overviewRow("Delivery", delivery, icon: "shippingbox")
        }
      } header: {
        sectionHeader("Overview", icon: "square.grid.2x2")
      }
    }
  }

  @ViewBuilder
  private var actionsSection: some View {
    if !store.snapshot.actions.isEmpty {
      Section {
        ForEach(store.snapshot.actions.prefix(6)) { command in
          SidebarPrimaryActionRow(title: command.title, systemImage: command.systemImage) {
            onRunCommand(command)
          }
          .help(command.detail ?? command.input)
        }
      } header: {
        sectionHeader("Actions", icon: "bolt")
      }
    }
  }

  private func metricsSection(_ section: PrjctDashboardSection) -> some View {
    let icon = Self.sectionIcon(section.title)
    return Section {
      ForEach(section.metrics.prefix(6)) { metric in
        metricRow(metric.label, metric.value, icon: icon)
      }
    } header: {
      sectionHeader(section.title, icon: icon)
    }
  }

  /// Same visual weight as the sidebar's own group headers (`prjct-code`,
  /// `prjct-cli`…): a full icon+bold-text row, not the muted system
  /// `Section(String)` label. The sidebar never uses that muted label for
  /// its groupings, so this panel shouldn't either.
  private func sectionHeader(_ title: String, icon: String) -> some View {
    Label {
      Text(title)
        .font(AppTypography.body.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
    } icon: {
      Image(systemName: icon)
        .font(AppTypography.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    }
    .labelStyle(.verticallyCentered)
    .sidebarRowGeometry()
  }

  /// One icon per dashboard section — same role as the folder/branch icon
  /// that opens every sidebar row, so a metric row reads as "icon, then
  /// text" like the left column instead of bare text.
  private static func sectionIcon(_ title: String) -> String {
    switch title {
    case "Value": "star"
    case "Performance": "speedometer"
    case "Quality": "checkmark.seal"
    case "Reliability": "shield"
    case "Cost": "dollarsign.circle"
    case "Review": "text.magnifyingglass"
    case "Workflow": "arrow.triangle.branch"
    default: "chart.bar"
    }
  }

  @ViewBuilder
  private var workflowSection: some View {
    if !store.snapshot.workflowRules.isEmpty || !store.snapshot.workflows.isEmpty {
      Section {
        ForEach(store.snapshot.workflowRules.prefix(3)) { rule in
          overviewRow(rule.title, rule.command, icon: "arrow.triangle.branch")
        }
        if !store.snapshot.workflows.isEmpty {
          // Same plain-row menu treatment as the sidebar's "Open source" /
          // "More" menus — a default Menu renders as a bordered popup button,
          // which is the one control style the left column never shows.
          Menu {
            ForEach(store.snapshot.workflows) { command in
              Button {
                onRunCommand(command)
              } label: {
                Label(command.title, systemImage: command.systemImage)
              }
            }
          } label: {
            SidebarPrimaryActionLabel(title: "Run workflow", systemImage: "checkmark.seal")
          }
          .buttonStyle(.plain)
          .menuIndicator(.hidden)
          .help("Run a prjct workflow")
        }
      } header: {
        sectionHeader("Workflow", icon: "arrow.triangle.branch")
      }
    }
  }

  /// Shared icon/geometry chrome for panel rows: leading icon in the
  /// sidebar's fixed icon column, `.verticallyCentered` label style, and
  /// `sidebarRowGeometry()`. Callers only vary the label content.
  private func sidebarIconLabel<Content: View>(
    icon: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Label {
      content()
    } icon: {
      Image(systemName: icon)
        .font(AppTypography.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: AppChromeMetrics.Sidebar.rowIconSize, height: AppChromeMetrics.Sidebar.rowIconSize)
    }
    .labelStyle(.verticallyCentered)
    .sidebarRowGeometry()
  }

  /// Same grammar as `SidebarRecentProjectRow`'s `projectLabel`: primary
  /// title line, secondary caption line below it. Values here are prose
  /// (risk summaries, shell commands), so the second line wraps instead of
  /// truncating.
  private func overviewRow(_ label: String, _ value: String, icon: String) -> some View {
    sidebarIconLabel(icon: icon) {
      VStack(alignment: .leading, spacing: 1) {
        Text(label)
          .font(AppTypography.body)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text(value)
          .font(AppTypography.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// Same grammar as `SidebarActiveProjectHeader`'s trailing count: primary
  /// title, and the short numeric value as a trailing monospaced badge —
  /// mirrors the "main  ^2" branch-row pattern instead of a plain label/value
  /// line.
  private func metricRow(_ label: String, _ value: String, icon: String) -> some View {
    sidebarIconLabel(icon: icon) {
      HStack(spacing: 8) {
        Text(label)
          .font(AppTypography.body)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer(minLength: 0)
        Text(value)
          .font(AppTypography.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
      }
    }
  }

  @ViewBuilder
  private var runsSection: some View {
    if !store.runs.isEmpty {
      Section {
        ForEach(store.runs) { run in
          DisclosureGroup {
            ScrollView {
              Text(run.outputTail.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
          } label: {
            HStack(spacing: 8) {
              runStatusIcon(run.status)
              Text(run.command.title)
                .font(AppTypography.footnote)
              Spacer()
              if run.status == .running {
                Button("Cancel") {
                  store.send(.cancelRun(runID: run.id))
                }
                .buttonStyle(.borderless)
                .font(AppTypography.caption)
              } else if let exitCode = run.exitCode, exitCode != 0 {
                Text("exit \(exitCode)")
                  .font(AppTypography.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .sidebarRowGeometry()
          }
        }
      } header: {
        sectionHeader("Runs", icon: "play.circle")
      }
    }
  }

  @ViewBuilder
  private func runStatusIcon(_ status: PrjctCommandRun.Status) -> some View {
    switch status {
    case .running:
      ProgressView().controlSize(.small)
    case .succeeded:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .failed:
      Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
    case .cancelled:
      Image(systemName: "stop.circle.fill").foregroundStyle(.secondary)
    }
  }
}

extension View {
  /// Same row grid as the left sidebar: `SidebarPrimaryActionLabel`'s
  /// horizontal geometry (leading inset 0 + 10pt padding, trailing inset 4)
  /// and `SidebarItemRow`'s 6pt vertical rhythm. Keeps panel rows from
  /// drifting onto the List default insets, which read as a different menu.
  fileprivate func sidebarRowGeometry() -> some View {
    padding(.horizontal, 10)
      .listRowInsets(.leading, 0)
      .listRowInsets(.trailing, 4)
      .listRowInsets(.vertical, 6)
  }
}
