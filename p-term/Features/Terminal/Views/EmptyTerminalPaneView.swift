import PTermSettingsShared
import SwiftUI

struct EmptyTerminalPaneView: View {
  let message: String
  var actionTitle: String? = nil
  var action: (() -> Void)? = nil

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
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .help(actionTitle)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
