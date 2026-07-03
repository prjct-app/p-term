import PTermSettingsShared
import SwiftUI

struct NotificationRowView: View {
  let notification: WorktreeTerminalNotification

  var body: some View {
    HStack(alignment: .top, spacing: AppChromeMetrics.Popover.rowSpacing) {
      Image(systemName: "bell")
        .foregroundStyle(notification.isRead ? Color.secondary : Color.orange)
        .frame(width: AppChromeMetrics.Popover.iconSize, height: AppChromeMetrics.Popover.iconSize)
        .accessibilityHidden(true)
      Text(notification.content)
        .font(AppTypography.caption)
        .foregroundStyle(notification.isRead ? Color.secondary : Color.primary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
  }
}
