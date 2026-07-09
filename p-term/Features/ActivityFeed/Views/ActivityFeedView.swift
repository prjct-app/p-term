import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

/// Global Activity Feed: a chronological, newest-first list of cross-worktree events (agent
/// notifications, script results). Read-only awareness — it reports what happened; it never
/// acts on the agent.
struct ActivityFeedView: View {
  let store: StoreOf<ActivityFeedFeature>

  var body: some View {
    Group {
      if store.visibleEvents.isEmpty {
        ContentUnavailableView {
          Label("No activity yet", systemImage: "sparkles")
        } description: {
          Text("Agent notifications and script results across your workspaces show up here.")
        }
      } else {
        List(store.visibleEvents) { event in
          if event.worktreeID != nil {
            Button {
              store.send(.activate(event))
            } label: {
              ActivityFeedRow(event: event)
            }
            .buttonStyle(.plain)
            .help("Jump to this workspace")
          } else {
            ActivityFeedRow(event: event)
          }
        }
        .listStyle(.inset)
      }
    }
    .navigationTitle("Activity")
    .frame(minWidth: 380, minHeight: 320)
    .toolbar {
      if !store.worktreeFilterOptions.isEmpty {
        ToolbarItem(placement: .automatic) {
          Menu {
            Button("All Workspaces") { store.send(.setFilter(nil)) }
            Divider()
            ForEach(store.worktreeFilterOptions, id: \.self) { worktreeID in
              Button(Self.label(for: worktreeID)) { store.send(.setFilter(worktreeID)) }
            }
          } label: {
            Label(currentFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
          }
          .help("Filter activity by workspace")
        }
      }
    }
  }

  private var currentFilterLabel: String {
    guard let filter = store.filterWorktreeID else { return "All Worktrees" }
    return Self.label(for: filter)
  }

  /// Human-readable label for a worktree id (a filesystem path) — its directory name.
  private static func label(for worktreeID: Worktree.ID) -> String {
    let name = URL(fileURLWithPath: worktreeID.rawValue).lastPathComponent
    return name.isEmpty ? worktreeID.rawValue : name
  }
}

/// Menu command that opens the Activity window. A dedicated view so it can read
/// `@Environment(\.openWindow)`, which isn't available directly inside a `CommandGroup`.
struct OpenActivityFeedButton: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Activity") { openWindow(id: WindowID.activity) }
      .help("Show the global activity feed")
  }
}

private struct ActivityFeedRow: View {
  let event: ActivityEvent

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbolName)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(event.title)
          .font(AppTypography.body)
        if let subtitle = event.subtitle {
          Text(subtitle)
            .font(AppTypography.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 8)
      Text(event.timestamp, format: .relative(presentation: .named))
        .font(AppTypography.caption)
        .foregroundStyle(.tertiary)
        .accessibilityLabel(Text(event.timestamp, format: .dateTime))
    }
    .padding(.vertical, 2)
  }

  private var symbolName: String {
    switch event.kind {
    case .notification: "bell.fill"
    case .scriptFinished(let success): success ? "checkmark.circle.fill" : "xmark.octagon.fill"
    }
  }

  private var tint: Color {
    switch event.kind {
    case .notification: .orange
    case .scriptFinished(let success): success ? .green : .red
    }
  }
}
