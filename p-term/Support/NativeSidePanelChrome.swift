import SwiftUI

struct NativeSideColumnWidth: Equatable {
  let minWidth: CGFloat
  let idealWidth: CGFloat
  let maxWidth: CGFloat

  static let sidebar = NativeSideColumnWidth(
    minWidth: AppChromeMetrics.Sidebar.minWidth,
    idealWidth: AppChromeMetrics.Sidebar.idealWidth,
    maxWidth: AppChromeMetrics.Sidebar.maxWidth
  )

  static let prjctPanel = NativeSideColumnWidth(
    minWidth: AppChromeMetrics.SidePanel.prjctMinWidth,
    idealWidth: AppChromeMetrics.SidePanel.prjctIdealWidth,
    maxWidth: AppChromeMetrics.SidePanel.prjctMaxWidth
  )
}

/// Shared split-column wrapper for side panels. Keep width/collapse behavior
/// here so the left sidebar and right-side panels do not drift into separate
/// layout implementations.
struct NativeSideColumn<Content: View>: View {
  let width: NativeSideColumnWidth
  var isVisible = true
  @ViewBuilder let content: () -> Content

  var body: some View {
    Group {
      if isVisible {
        content()
      } else {
        Color.clear
      }
    }
    .navigationSplitViewColumnWidth(
      min: isVisible ? width.minWidth : 0,
      ideal: isVisible ? width.idealWidth : 0,
      max: isVisible ? width.maxWidth : 0
    )
  }
}

struct NativeSidePanelHeader<Icon: View, Accessory: View, Actions: View>: View {
  let title: String
  let subtitle: String?
  @ViewBuilder let icon: () -> Icon
  @ViewBuilder let accessory: () -> Accessory
  @ViewBuilder let actions: () -> Actions

  init(
    title: String,
    subtitle: String? = nil,
    @ViewBuilder icon: @escaping () -> Icon,
    @ViewBuilder accessory: @escaping () -> Accessory,
    @ViewBuilder actions: @escaping () -> Actions
  ) {
    self.title = title
    self.subtitle = subtitle
    self.icon = icon
    self.accessory = accessory
    self.actions = actions
  }

  var body: some View {
    HStack(spacing: 8) {
      icon()
        .frame(width: 20, height: 20)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)

        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      .layoutPriority(1)

      Spacer(minLength: 8)

      accessory()

      actions()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(minHeight: 44)
    .background(.bar)
  }
}

extension NativeSidePanelHeader where Accessory == EmptyView {
  init(
    title: String,
    subtitle: String? = nil,
    @ViewBuilder icon: @escaping () -> Icon,
    @ViewBuilder actions: @escaping () -> Actions
  ) {
    self.init(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accessory: { EmptyView() },
      actions: actions
    )
  }
}

struct NativeSidePanelIconButton: View {
  let systemImage: String
  let help: String
  var isEnabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 12))
        .frame(width: 22, height: 22)
    }
    .buttonStyle(.borderless)
    .help(help)
    .disabled(!isEnabled)
  }
}
