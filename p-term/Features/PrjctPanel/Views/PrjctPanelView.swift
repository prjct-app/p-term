import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

struct PrjctPanelView: View {
  @Bindable var store: StoreOf<PrjctPanelFeature>
  let onRunCommand: (PrjctTerminalCommand) -> Void

  var body: some View {
    // Native sidebar list — same `List(.sidebar)` chrome as the left sidebar,
    // no custom background or card surfaces.
    List {
      if store.snapshot.isEnabled {
        overviewSection
        actionsSection
        ForEach(store.snapshot.sections) { section in
          metricsSection(section)
        }
        workflowSection
      } else {
        Section {
          ContentUnavailableView {
            Label("No prjct project", systemImage: "folder.badge.questionmark")
          }
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .top, spacing: 0) { header }
  }

  private var header: some View {
    HStack(spacing: 8) {
      PrjctLogoView(size: 20)
      Text("prjct")
        .font(.headline)
      Text(store.snapshot.headline)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 0)
      if store.isLoading {
        ProgressView()
          .controlSize(.small)
      }
      Button {
        store.send(.refresh)
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.borderless)
      .help("Refresh prjct dashboard")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private var overviewSection: some View {
    let config = store.snapshot.config
    if config?.projectID != nil || config?.persona != nil || store.snapshot.reviewRisk != nil
      || store.snapshot.delivery != nil
    {
      Section("Overview") {
        if let projectID = config?.projectID {
          LabeledContent("Project", value: projectID)
        }
        if let persona = config?.persona {
          LabeledContent("Persona", value: persona)
        }
        if let risk = store.snapshot.reviewRisk {
          LabeledContent("Review risk", value: risk)
        }
        if let delivery = store.snapshot.delivery {
          LabeledContent("Delivery", value: delivery)
        }
      }
    }
  }

  @ViewBuilder
  private var actionsSection: some View {
    if !store.snapshot.actions.isEmpty {
      Section("Actions") {
        ForEach(store.snapshot.actions.prefix(6)) { command in
          Button {
            onRunCommand(command)
          } label: {
            Label(command.title, systemImage: command.systemImage)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .help(command.detail ?? command.input)
        }
      }
    }
  }

  private func metricsSection(_ section: PrjctDashboardSection) -> some View {
    Section(section.title) {
      ForEach(section.metrics.prefix(6)) { metric in
        LabeledContent(metric.label) {
          Text(metric.value)
            .monospacedDigit()
            .lineLimit(1)
        }
      }
    }
  }

  @ViewBuilder
  private var workflowSection: some View {
    if !store.snapshot.workflowRules.isEmpty || !store.snapshot.workflows.isEmpty {
      Section("Workflow") {
        ForEach(store.snapshot.workflowRules.prefix(3)) { rule in
          LabeledContent(rule.title, value: rule.command)
        }
        if !store.snapshot.workflows.isEmpty {
          Menu {
            ForEach(store.snapshot.workflows) { command in
              Button {
                onRunCommand(command)
              } label: {
                Label(command.title, systemImage: command.systemImage)
              }
            }
          } label: {
            Label("Run workflow", systemImage: "checkmark.seal")
          }
        }
      }
    }
  }
}

struct PrjctLogoView: View {
  let size: CGFloat

  var body: some View {
    Image("prjct-mark")
      .resizable()
      .aspectRatio(contentMode: .fit)
      .padding(size * 0.16)
      .frame(width: size, height: size)
      .background(.bar.shadow(.drop(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)), in: .circle)
      .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
      .accessibilityLabel("prjct")
  }
}
