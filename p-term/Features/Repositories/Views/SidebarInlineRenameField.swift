import PTermSettingsShared
import SwiftUI

/// The shared inline-rename text field used by every renameable sidebar row
/// (terminal pane, recents row, project header). Owns the field MECHANICS —
/// focus seeding on appear, submit, Escape-cancel, and the focus-loss commit
/// that pairs with `onSubmit` (each row's `isRenaming` guard makes the second
/// call a no-op). Each row keeps its own commit POLICY (what an empty or
/// unchanged draft means) — that's the SRP cut: mechanics here, policy there.
struct SidebarInlineRenameField: View {
  @Binding var text: String
  var font: Font = AppTypography.body
  let accessibilityLabel: String
  let onCommit: () -> Void
  let onCancel: () -> Void
  @FocusState private var focused: Bool

  var body: some View {
    TextField("Name", text: $text)
      .textFieldStyle(.plain)
      .font(font)
      .focused($focused)
      .onSubmit(onCommit)
      .onExitCommand(perform: onCancel)
      .onAppear { focused = true }
      .onChange(of: focused) { _, isFocused in
        if !isFocused { onCommit() }
      }
      .accessibilityLabel(accessibilityLabel)
  }
}
