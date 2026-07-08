import SwiftUI

extension View {
  /// Shared chrome for a settings page's top-level `Form`: grouped style plus
  /// the negative padding that pulls it flush with the settings window's
  /// own margins. Used by every settings tab so a future tweak doesn't need
  /// to be repeated per page.
  func settingsFormChrome() -> some View {
    formStyle(.grouped)
      .padding(.top, -20)
      .padding(.leading, -8)
      .padding(.trailing, -6)
  }
}
