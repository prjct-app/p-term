import SwiftUI

struct WindowCommands: Commands {
  let ghosttyShortcuts: GhosttyShortcutManager
  @FocusedValue(\.closeSurfaceAction) private var closeSurfaceAction
  @FocusedValue(\.closeTabAction) private var closeTabAction
  @FocusedValue(\.terminateAllTerminalSessionsAction) private var terminateAllTerminalSessionsAction

  var body: some Commands {
    let closeSurfaceHotkey = ghosttyShortcuts.keyboardShortcut(for: "close_surface")
    let isCloseSurfaceOverlapping = closeSurfaceHotkey?.key == "w" && closeSurfaceHotkey?.modifiers == .command

    let closeSurfaceEnabled = closeSurfaceAction?.isEnabled == true
    let closeSurfaceDisplay = ghosttyShortcuts.display(for: "close_surface")
    CommandGroup(replacing: .saveItem) {
      Button("Close Terminal", systemImage: "xmark") {
        closeSurfaceAction?()
      }
      // Suppress the Ghostty shortcut when the close-surface action is unavailable so Close Window can claim ⌘W.
      .keyboardShortcut(closeSurfaceEnabled ? ghosttyShortcuts.keyboardShortcut(for: "close_surface") : nil)
      .help(closeSurfaceEnabled ? tooltip("Close Terminal", display: closeSurfaceDisplay) : "Close Terminal")
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
      .help("Terminate every running terminal session across all worktrees")
      .disabled(terminateAllTerminalSessionsAction?.isEnabled != true)

      Button("Close Window") {
        NSApplication.shared.keyWindow?.performClose(nil)
      }
      .help("Close the current window (⌘W)")
      .keyboardShortcut(!isCloseSurfaceOverlapping || !closeSurfaceEnabled ? .init("w") : nil)
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
