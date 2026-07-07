import ComposableArchitecture
import SwiftUI

public struct NotificationsSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  public init(store: StoreOf<SettingsFeature>) {
    self.store = store
  }

  public var body: some View {
    Form {
      Section {
        Toggle(
          isOn: $store.systemNotificationsEnabled
        ) {
          Text("System notifications")
        }
        .help("Show macOS system notifications")
        Toggle(
          isOn: $store.notificationSoundEnabled
        ) {
          Text("Play notification sound")
          Text(
            "Ignored when system notifications are enabled, as they play sounds"
              + " according to your settings."
          )
        }.disabled(store.systemNotificationsEnabled)
      }
      Section("Worktrees") {
        Toggle(
          isOn: $store.inAppNotificationsEnabled
        ) {
          Text("Notification badge")
          Text("Display an orange dot next to worktrees with unread notifications.")
        }
        Toggle(
          isOn: $store.moveNotifiedWorktreeToTop
        ) {
          Text("Prioritize unread worktrees")
          Text("Worktrees with unread notifications will be shown first in the list.")
        }
      }
      Section("Agents") {
        Toggle(
          isOn: $store.agentFinishedNotificationsEnabled
        ) {
          Text("Notify when an agent finishes")
          Text("Shown when a busy agent (Claude, Codex, etc.) goes idle in a background pane.")
        }
        Toggle(
          isOn: $store.agentAwaitingInputNotificationsEnabled
        ) {
          Text("Notify when an agent needs input")
          Text("Shown when an agent starts waiting on you in a background pane.")
        }
      }
    }
    .formStyle(.grouped)
    .padding(.top, -20)
    .padding(.leading, -8)
    .padding(.trailing, -6)

    .navigationTitle("Notifications")
  }
}
