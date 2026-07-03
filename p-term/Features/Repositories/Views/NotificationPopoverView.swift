import PTermSettingsShared
import SwiftUI

struct NotificationPopoverView: View {
  let notifications: [WorktreeTerminalNotification]
  @Environment(\.focusNotificationAction) private var focusNotificationAction: (WorktreeTerminalNotification) -> Void

  var body: some View {
    let count = notifications.count
    let countLabel = count == 1 ? "notification" : "notifications"
    ScrollView {
      VStack(alignment: .leading) {
        Text("Notifications")
          .font(AppTypography.headline)
        Text("\(count) \(countLabel)")
          .font(AppTypography.subheadline)
          .foregroundStyle(.secondary)
        Divider()
        ForEach(notifications) { notification in
          Button {
            focusNotificationAction(notification)
          } label: {
            NotificationRowView(notification: notification)
          }
          .buttonStyle(.plain)
          .help(notification.content.isEmpty ? "Focus pane" : notification.content)
        }
      }
      .padding()
    }
    .frame(minWidth: 260, maxWidth: 480, maxHeight: 400)
  }
}
