import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

struct PrjctPanelView: View {
  @Bindable var store: StoreOf<PrjctPanelFeature>
  let onRunCommand: (PrjctTerminalCommand) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if store.snapshot.isEnabled {
            overview
            actionGrid
            metricSections
            workflowSummary
          } else {
            ContentUnavailableView {
              Label("No prjct project", systemImage: "folder.badge.questionmark")
            }
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
    .background(.bar)
  }

  private var header: some View {
    HStack(spacing: 10) {
      PrjctLogoView(size: 26)
      VStack(alignment: .leading, spacing: 2) {
        Text("prjct")
          .font(AppTypography.headline)
        Text(store.snapshot.headline)
          .font(AppTypography.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
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
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private var overview: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let projectID = store.snapshot.config?.projectID {
        compactRow("Project", projectID)
      }
      if let persona = store.snapshot.config?.persona {
        compactRow("Persona", persona)
      }
      if let risk = store.snapshot.reviewRisk {
        compactRow("Review risk", risk)
      }
      if let delivery = store.snapshot.delivery {
        compactRow("Delivery", delivery)
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  @ViewBuilder
  private var actionGrid: some View {
    if !store.snapshot.actions.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Actions")
          .font(AppTypography.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
          ForEach(store.snapshot.actions.prefix(6)) { command in
            Button {
              onRunCommand(command)
            } label: {
              Label(command.title, systemImage: command.systemImage)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .controlSize(.small)
            .help(command.detail ?? command.input)
          }
        }
      }
    }
  }

  private var metricSections: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(store.snapshot.sections) { section in
        dashboardCard(section)
      }
    }
  }

  @ViewBuilder
  private var workflowSummary: some View {
    if !store.snapshot.workflowRules.isEmpty || !store.snapshot.workflows.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Workflow")
          .font(AppTypography.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        if !store.snapshot.workflowRules.isEmpty {
          ForEach(store.snapshot.workflowRules.prefix(3)) { rule in
            compactRow(rule.title, rule.command)
          }
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
          .controlSize(.small)
        }
      }
      .padding(12)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func dashboardCard(_ section: PrjctDashboardSection) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(section.title)
        .font(AppTypography.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
        ForEach(section.metrics.prefix(6)) { metric in
          VStack(alignment: .leading, spacing: 4) {
            Text(metric.label)
              .font(AppTypography.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            Text(metric.value)
              .font(AppTypography.callout.weight(.semibold))
              .monospacedDigit()
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func compactRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(AppTypography.caption)
        .foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Text(value)
        .font(AppTypography.caption)
        .lineLimit(2)
        .multilineTextAlignment(.trailing)
        .textSelection(.enabled)
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
