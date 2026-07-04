import PTermSettingsShared
import SwiftUI

enum AppDesign {
  enum Radius {
    static let row: CGFloat = 12
    static let panel: CGFloat = 10
    static let icon: CGFloat = 9
    static let toolbar: CGFloat = 999
  }

  enum Size {
    static let rowMinHeight: CGFloat = 58
    static let iconContainer: CGFloat = 30
    static let icon: CGFloat = 16
    static let toolbarControlHeight: CGFloat = 24
  }

  enum Spacing {
    static let inline: CGFloat = 10
    static let rowContent: CGFloat = 10
    static let section: CGFloat = 22
    static let sectionHeader: CGFloat = 8
    static let panelContent: CGFloat = 8
  }

  enum Padding {
    static let rowHorizontal: CGFloat = 14
    static let rowVertical: CGFloat = 9
    static let panel: CGFloat = 12
    static let toolbarHorizontal: CGFloat = 10
    static let toolbarVertical: CGFloat = 4
  }

  enum Stroke {
    static let subtleOpacity: Double = 0.07
    static let tintedOpacity: Double = 0.22
  }

  enum Welcome {
    static let contentWidth: CGFloat = 520
    static let contentPadding: CGFloat = 52
    static let verticalPadding: CGFloat = 48
    static let logoWidth: CGFloat = 104
  }
}

struct AppIconContainer<Icon: View>: View {
  @ViewBuilder let icon: () -> Icon

  var body: some View {
    icon()
      .font(AppTypography.callout)
      .frame(width: AppDesign.Size.iconContainer, height: AppDesign.Size.iconContainer)
      .foregroundStyle(.secondary)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.icon, style: .continuous))
      .accessibilityHidden(true)
  }
}

struct AppSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(AppTypography.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
  }
}

struct AppRowSurface: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.row, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: AppDesign.Radius.row, style: .continuous)
          .stroke(.primary.opacity(AppDesign.Stroke.subtleOpacity), lineWidth: 1)
      }
  }
}

extension View {
  func appRowSurface() -> some View {
    modifier(AppRowSurface())
  }
}

struct AppActionRow<Leading: View, Trailing: View>: View {
  let title: String
  let subtitle: String?
  let action: () -> Void
  @ViewBuilder let leading: () -> Leading
  @ViewBuilder let trailing: () -> Trailing

  var body: some View {
    Button(action: action) {
      HStack(spacing: AppDesign.Spacing.rowContent) {
        leading()

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(AppTypography.body.weight(.semibold))
            .foregroundStyle(.primary)
          if let subtitle {
            Text(subtitle)
              .font(AppTypography.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: 0)
        trailing()
          .font(AppTypography.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, AppDesign.Padding.rowHorizontal)
      .padding(.vertical, AppDesign.Padding.rowVertical)
      .frame(maxWidth: .infinity, minHeight: AppDesign.Size.rowMinHeight, alignment: .leading)
      .appRowSurface()
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

extension AppActionRow where Trailing == Image {
  init(
    title: String,
    subtitle: String?,
    action: @escaping () -> Void,
    @ViewBuilder leading: @escaping () -> Leading
  ) {
    self.title = title
    self.subtitle = subtitle
    self.action = action
    self.leading = leading
    self.trailing = {
      Image(systemName: "arrow.right")
    }
  }
}
