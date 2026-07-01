import ComposableArchitecture
import SupacodeSettingsShared
import SwiftUI

public struct TypographySettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  public init(store: StoreOf<SettingsFeature>) {
    self.store = store
  }

  private var terminalFontFamily: String? {
    store.terminalFontSelection.familyName
  }

  private var terminalFontIsMonospace: Bool {
    guard let terminalFontFamily else { return true }
    return FontFamilyResolver.isMonospace(family: terminalFontFamily)
  }

  private var terminalPreviewFont: Font {
    guard let terminalFontFamily, let name = FontFamilyResolver.regularFontName(forFamily: terminalFontFamily) else {
      return .system(.body, design: .monospaced)
    }
    return .custom(name, size: 13)
  }

  public var body: some View {
    Form {
      Section {
        LabeledContent("App Font") {
          FontFamilyPicker(selection: $store.uiFontSelection)
        }
        Text("Supacode uses this font throughout the sidebar, toolbar, and settings.")
          .font(AppTypography.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Interface")
      }
      Section {
        LabeledContent("Terminal Font") {
          FontFamilyPicker(selection: $store.terminalFontSelection, showsMonospaceFilter: true)
        }
        if !terminalFontIsMonospace {
          Label("May render unevenly in the terminal.", systemImage: "exclamationmark.triangle")
            .font(AppTypography.caption)
            .foregroundStyle(.secondary)
        }
        Text("supacode$ echo \"Hello, Supacode\"")
          .font(terminalPreviewFont)
          .foregroundStyle(.secondary)
      } header: {
        Text("Terminal")
      } footer: {
        Text("Applies even when Supacode Terminal Theme is off.")
      }
    }
    .formStyle(.grouped)
    .padding(.top, -20)
    .padding(.leading, -8)
    .padding(.trailing, -6)
    .navigationTitle("Typography")
  }
}
