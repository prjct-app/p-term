import SwiftUI

struct WindowCommands: Commands {
  let ghosttyShortcuts: GhosttyShortcutManager
  @FocusedValue(\.closeSurfaceAction) private var closeSurfaceAction
  @FocusedValue(\.closeTabAction) private var closeTabAction
  @FocusedValue(\.terminateAllTerminalSessionsAction) private var terminateAllTerminalSessionsAction

  var body: some Commands {
    let closeSurfaceEnabled = closeSurfaceAction?.isEnabled == true
    CommandGroup(replacing: .saveItem) {
      Button("Close Terminal", systemImage: "xmark") {
        closeSurfaceAction?()
      }
      // Claim ⌘W directly (not via the Ghostty binding, which the user may have
      // remapped/unbound) whenever a terminal is focused, so ⌘W closes the
      // focused terminal — never the whole window. Falls back to no shortcut
      // when there's no terminal, letting Close Window reclaim ⌘W.
      .keyboardShortcut(closeSurfaceEnabled ? KeyboardShortcut("w", modifiers: .command) : nil)
      // Mirror the shortcut's conditionality: when no terminal is focused the
      // disabled item must not advertise ⌘W (Close Window owns it then).
      .help(closeSurfaceEnabled ? "Close the focused terminal (⌘W)" : "Close the focused terminal")
      .disabled(!closeSurfaceEnabled)

      Button("Close Terminal Tab") {
        closeTabAction?()
      }
      .ghosttyKeyboardShortcut("close_tab", in: ghosttyShortcuts)
      .help(tooltip("Close Terminal Tab", display: ghosttyShortcuts.display(for: "close_tab")))
      .disabled(closeTabAction?.isEnabled != true)

      Button("Terminate All Terminal Sessions…") {
        terminateAllTerminalSessionsAction?()
      }
      .help("Terminate every running terminal session across all workspaces")
      .disabled(terminateAllTerminalSessionsAction?.isEnabled != true)

      Button("Close Window") {
        NSApplication.shared.keyWindow?.performClose(nil)
      }
      // ⌘⇧W while a terminal is focused (⌘W closes the terminal); plain ⌘W only
      // when there's no terminal to close.
      .keyboardShortcut(
        closeSurfaceEnabled
          ? KeyboardShortcut("w", modifiers: [.command, .shift])
          : KeyboardShortcut("w", modifiers: .command)
      )
      .help(closeSurfaceEnabled ? "Close the current window (⌘⇧W)" : "Close the current window (⌘W)")
    }
  }

  /// `<label> (<hotkey>)` tooltip; falls back to just the label when the action is unbound.
  private func tooltip(_ label: String, display: String?) -> String {
    guard let display else { return label }
    return "\(label) (\(display))"
  }
}

private struct TerminateAllTerminalSessionsActionKey: FocusedValueKey {
  typealias Value = FocusedAction<Void>
}

extension FocusedValues {
  /// Wired as a scene action so the menu enable state tracks app-wide surface
  /// presence, not the currently-selected worktree.
  var terminateAllTerminalSessionsAction: FocusedAction<Void>? {
    get { self[TerminateAllTerminalSessionsActionKey.self] }
    set { self[TerminateAllTerminalSessionsActionKey.self] = newValue }
  }
}
