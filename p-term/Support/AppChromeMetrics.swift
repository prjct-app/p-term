import Foundation

enum AppChromeMetrics {
  enum Toolbar {
    static let controlHeight: CGFloat = AppDesign.Size.toolbarControlHeight
    static let iconSize: CGFloat = AppDesign.Size.icon
    static let horizontalPadding: CGFloat = AppDesign.Padding.toolbarHorizontal
    static let verticalPadding: CGFloat = AppDesign.Padding.toolbarVertical
    static let contentSpacing: CGFloat = 6
  }

  enum Sidebar {
    static let minWidth: CGFloat = 220
    static let idealWidth: CGFloat = 260
    static let maxWidth: CGFloat = 320
    static let rowIconSize: CGFloat = AppDesign.Size.icon
    static let rowTextIndent: CGFloat = 24
    static let rowBadgeSize: CGFloat = 10
    static let statusDotSize: CGFloat = 6
    static let cardActionSize: CGFloat = 20
    static let accessorySpacing: CGFloat = 6
  }

  enum SidePanel {
    static let prjctMinWidth: CGFloat = 320
    static let prjctIdealWidth: CGFloat = 380
    static let prjctMaxWidth: CGFloat = 560
    static let diffMinWidth: CGFloat = 720
    static let diffIdealWidth: CGFloat = 960
    static let diffSidebarWidth: CGFloat = 300
  }

  enum Popover {
    static let iconSize: CGFloat = AppDesign.Size.icon
    static let statusDotSize: CGFloat = 6
    static let rowSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
  }
}
