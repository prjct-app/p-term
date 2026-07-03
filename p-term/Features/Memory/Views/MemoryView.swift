import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

/// The native Memory surface — search the project's prjct memory (decisions, gotchas, learnings…)
/// right in p/term. Free + local; makes the ecosystem *felt*. Dumb MVVM view over `MemoryFeature`.
struct MemoryView: View {
  @Bindable var store: StoreOf<MemoryFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      searchField
      Divider()
      content
    }
    .frame(minWidth: 420, minHeight: 360)
    .navigationTitle("Memory")
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField("Search project memory", text: $store.query.sending(\.queryChanged))
        .textFieldStyle(.plain)
        .font(AppTypography.body)
      if store.isSearching {
        ProgressView().controlSize(.small)
      }
    }
    .padding(12)
  }

  @ViewBuilder
  private var content: some View {
    if store.query.trimmingCharacters(in: .whitespaces).isEmpty {
      ContentUnavailableView {
        Label("Search the project's memory", systemImage: "brain")
      } description: {
        Text("Decisions, gotchas, learnings, patterns and specs this project has accumulated.")
      }
    } else if store.entries.isEmpty && !store.isSearching {
      ContentUnavailableView.search(text: store.query)
    } else {
      List(store.entries) { entry in
        MemoryRow(entry: entry)
      }
      .listStyle(.inset)
    }
  }
}

private struct MemoryRow: View {
  let entry: MemoryEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.type.uppercased())
        .font(AppTypography.caption.monospaced())
        .foregroundStyle(tint)
        .accessibilityLabel(Text("\(entry.type) memory"))
      Text(entry.content)
        .font(AppTypography.callout)
        .lineLimit(4)
    }
    .padding(.vertical, 2)
  }

  private var tint: Color {
    switch entry.type.lowercased() {
    case "decision": .blue
    case "gotcha", "anti-pattern": .red
    case "learning": .green
    case "pattern": .purple
    case "spec": .teal
    default: .secondary
    }
  }
}

/// Menu command that opens the Memory window. Dedicated view for `@Environment(\.openWindow)`,
/// unavailable directly inside a `CommandGroup`.
struct OpenMemoryButton: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Memory") { openWindow(id: WindowID.memory) }
      .help("Search this project's prjct memory")
  }
}
