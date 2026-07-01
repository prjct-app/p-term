import SupacodeSettingsShared
import SwiftUI

/// Searchable "any installed font" picker, shared between the app-UI and
/// terminal font settings rows. Deliberately not a curated swatch list like
/// `ColorSwatchRow`: `FontFamilyResolver.allFamilies` can return hundreds of
/// entries, and the personalization feature intentionally has no
/// curated/blocked set of fonts.
public struct FontFamilyPicker: View {
  @Binding var selection: AppFontSelection
  var showsMonospaceFilter: Bool
  var previewText: String

  @State private var isPresented = false
  @State private var query = ""
  @State private var monospaceOnly: Bool

  public init(
    selection: Binding<AppFontSelection>,
    showsMonospaceFilter: Bool = false,
    previewText: String = "The quick brown fox jumps"
  ) {
    _selection = selection
    self.showsMonospaceFilter = showsMonospaceFilter
    self.previewText = previewText
    _monospaceOnly = State(initialValue: showsMonospaceFilter)
  }

  private var displayName: String {
    selection.familyName ?? "System Default"
  }

  public var body: some View {
    HStack(spacing: 8) {
      Text(displayName)
        .foregroundStyle(.secondary)
      Button("Change…") { isPresented = true }
        .help("Browse fonts installed on this Mac.")
    }
    .popover(isPresented: $isPresented) {
      FontFamilyPickerContent(
        selection: $selection,
        showsMonospaceFilter: showsMonospaceFilter,
        previewText: previewText,
        query: $query,
        monospaceOnly: $monospaceOnly
      )
    }
  }
}

private struct FontFamilyPickerContent: View {
  @Binding var selection: AppFontSelection
  let showsMonospaceFilter: Bool
  let previewText: String
  @Binding var query: String
  @Binding var monospaceOnly: Bool

  private var filteredFamilies: [String] {
    let families = FontFamilyResolver.allFamilies
    let byQuery = query.isEmpty ? families : families.filter { $0.localizedCaseInsensitiveContains(query) }
    guard showsMonospaceFilter, monospaceOnly else { return byQuery }
    return byQuery.filter { FontFamilyResolver.isMonospace(family: $0) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField("Search fonts", text: $query)
        .textFieldStyle(.roundedBorder)
        .padding(8)
      if showsMonospaceFilter {
        Toggle("Monospace only", isOn: $monospaceOnly)
          .toggleStyle(.checkbox)
          .padding(.horizontal, 8)
          .padding(.bottom, 4)
          .help("Filter to fixed-width fonts, better suited for terminal output.")
      }
      Divider()
      List {
        Button {
          selection = .systemDefault
        } label: {
          FontFamilyRow(family: nil, previewText: previewText, isSelected: selection == .systemDefault)
        }
        .buttonStyle(.plain)
        .help("System Default")
        Divider()
        ForEach(filteredFamilies, id: \.self) { family in
          Button {
            selection = .custom(familyName: family)
          } label: {
            FontFamilyRow(family: family, previewText: previewText, isSelected: selection.familyName == family)
          }
          .buttonStyle(.plain)
          .help(family)
        }
      }
      .listStyle(.plain)
    }
    .frame(width: 320, height: 360)
  }
}

private struct FontFamilyRow: View {
  let family: String?
  let previewText: String
  let isSelected: Bool

  private var resolvedFontName: String? {
    family.flatMap(FontFamilyResolver.regularFontName(forFamily:))
  }

  private var previewFont: Font {
    guard let resolvedFontName else { return .system(.caption) }
    return .custom(resolvedFontName, size: 12)
  }

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(family ?? "System Default")
          .font(AppTypography.callout)
        Text(previewText)
          .font(previewFont)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if isSelected {
        Image(systemName: "checkmark")
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
      }
    }
    .contentShape(Rectangle())
    .padding(.vertical, 2)
  }
}
