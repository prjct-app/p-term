import SupacodeSettingsShared
import SwiftUI

struct EmptyTerminalPaneView: View {
  let message: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "apple.terminal.on.rectangle")
        .font(AppTypography.title)
        .imageScale(.large)
        .accessibilityHidden(true)
        .foregroundStyle(.secondary)
      VStack(spacing: 4) {
        Text(message)
          .font(AppTypography.title3)
        Text("Use the \(Text("+").bold()) button to open a terminal.")
          .font(AppTypography.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
