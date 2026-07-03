import Foundation

enum AppChromeMetrics {
  enum Toolbar {
    static let controlHeight: CGFloat = 24
    static let iconSize: CGFloat = 16
    static let titleIconContainerSize: CGFloat = 24
    static let titleAvatarSize: CGFloat = 22
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 4
    static let contentSpacing: CGFloat = 6
  }

  enum Sidebar {
    static let rowIconSize: CGFloat = 16
    static let rowTextIndent: CGFloat = 24
    static let rowBadgeSize: CGFloat = 10
    static let statusDotSize: CGFloat = 6
    static let cardActionSize: CGFloat = 20
    static let accessorySpacing: CGFloat = 6
  }

  enum Popover {
    static let iconSize: CGFloat = 16
    static let statusDotSize: CGFloat = 6
    static let rowSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
  }
}
