import PTermSettingsShared
import SwiftUI

/// Shared layout tokens + liquid-glass surfaces. Prefer these helpers over
/// one-off materials so sidebar cards, empty states, rows, and toolbar pills
/// stay visually coherent (native macOS 26 glass, continuous corners).
enum AppDesign {
  enum Radius {
    static let row: CGFloat = 12
    static let panel: CGFloat = 12
    static let card: CGFloat = 16
    static let icon: CGFloat = 10
    static let toolbar: CGFloat = 999
  }

  enum Size {
    static let rowMinHeight: CGFloat = 58
    static let iconContainer: CGFloat = 32
    static let icon: CGFloat = 16
    static let heroIcon: CGFloat = 44
    static let toolbarControlHeight: CGFloat = 24
  }

  enum Spacing {
    static let inline: CGFloat = 10
    static let rowContent: CGFloat = 10
    static let section: CGFloat = 22
    static let sectionHeader: CGFloat = 8
    static let panelContent: CGFloat = 8
    static let hero: CGFloat = 16
  }

  enum Padding {
    static let rowHorizontal: CGFloat = 14
    static let rowVertical: CGFloat = 9
    static let panel: CGFloat = 14
    static let card: CGFloat = 20
    static let toolbarHorizontal: CGFloat = 10
    static let toolbarVertical: CGFloat = 4
  }

  enum Stroke {
    static let subtleOpacity: Double = 0.08
    static let tintedOpacity: Double = 0.22
    static let glassOpacity: Double = 0.12
  }

  /// Continuous shapes used with `.glassEffect` so every surface shares the
  /// same corner language (Liquid Glass prefers continuous curves).
  enum Shape {
    static func row(_ radius: CGFloat = Radius.row) -> RoundedRectangle {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static func panel(_ radius: CGFloat = Radius.panel) -> RoundedRectangle {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static func card(_ radius: CGFloat = Radius.card) -> RoundedRectangle {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static var capsule: Capsule { Capsule(style: .continuous) }
  }
}

// MARK: - Liquid glass surfaces

/// Fills + glass + hairline stroke for elevated chrome (cards, empty-state
/// panels, notices). Callers supply an optional tint wash for semantic color.
struct AppGlassSurface: ViewModifier {
  enum Style {
    case row
    case panel
    case card
    case capsule
  }

  var style: Style = .row
  var tint: Color?
  var tintOpacity: Double = 0.08

  func body(content: Content) -> some View {
    switch style {
    case .row:
      content.modifier(
        AppGlassShapeSurface(
          shape: AppDesign.Shape.row(),
          tint: tint,
          tintOpacity: tintOpacity
        )
      )
    case .panel:
      content.modifier(
        AppGlassShapeSurface(
          shape: AppDesign.Shape.panel(),
          tint: tint,
          tintOpacity: tintOpacity
        )
      )
    case .card:
      content.modifier(
        AppGlassShapeSurface(
          shape: AppDesign.Shape.card(),
          tint: tint,
          tintOpacity: tintOpacity
        )
      )
    case .capsule:
      content.modifier(
        AppGlassShapeSurface(
          shape: AppDesign.Shape.capsule,
          tint: tint,
          tintOpacity: tintOpacity
        )
      )
    }
  }
}

private struct AppGlassShapeSurface<S: InsettableShape>: ViewModifier {
  let shape: S
  var tint: Color?
  var tintOpacity: Double = 0.08

  func body(content: Content) -> some View {
    content
      .background {
        shape.fill(tint?.opacity(tintOpacity) ?? Color.clear)
      }
      .glassEffect(.regular, in: shape)
      .overlay {
        shape.strokeBorder(Color.primary.opacity(AppDesign.Stroke.glassOpacity), lineWidth: 1)
      }
  }
}

extension View {
  func appGlassSurface(
    _ style: AppGlassSurface.Style = .row,
    tint: Color? = nil,
    tintOpacity: Double = 0.08
  ) -> some View {
    modifier(AppGlassSurface(style: style, tint: tint, tintOpacity: tintOpacity))
  }

  /// Prefer over ad-hoc materials for list-like rows.
  func appRowSurface() -> some View {
    appGlassSurface(.row)
  }
}

// MARK: - Building blocks

struct AppIconContainer<Icon: View>: View {
  var prominent = false
  @ViewBuilder let icon: () -> Icon

  var body: some View {
    icon()
      .font(prominent ? AppTypography.title3.weight(.semibold) : AppTypography.callout)
      .frame(
        width: prominent ? AppDesign.Size.heroIcon : AppDesign.Size.iconContainer,
        height: prominent ? AppDesign.Size.heroIcon : AppDesign.Size.iconContainer
      )
      .foregroundStyle(prominent ? .primary : .secondary)
      .background {
        AppDesign.Shape.row(prominent ? 14 : AppDesign.Radius.icon)
          .fill(.quaternary.opacity(prominent ? 0.35 : 0.5))
      }
      .glassEffect(
        .regular,
        in: AppDesign.Shape.row(prominent ? 14 : AppDesign.Radius.icon)
      )
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
      .tracking(0.4)
  }
}

/// Primary CTA used in empty states and welcome surfaces — glass capsule +
/// semibold label so the next action is obvious without looking like a web button.
struct AppPrimaryButton: View {
  let title: String
  var systemImage: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let systemImage {
          Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .accessibilityHidden(true)
        }
        Text(title)
          .font(AppTypography.body.weight(.semibold))
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 10)
      .frame(minHeight: 36)
    }
    .buttonStyle(.plain)
    .background {
      Capsule(style: .continuous)
        .fill(Color.accentColor.opacity(0.18))
    }
    .glassEffect(.regular, in: Capsule(style: .continuous))
    .overlay {
      Capsule(style: .continuous)
        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
    }
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
