import SwiftUI

struct ToolbarControlWidth: Equatable {
  let min: CGFloat?
  let ideal: CGFloat?
  let max: CGFloat?

  init(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) {
    self.min = min
    self.ideal = ideal
    self.max = max
  }
}

/// Shared toolbar control for pill/split buttons: one primary action plus an
/// optional selector menu, with icon and label supplied by the caller.
struct ToolbarControlButton<MenuContent: View, Icon: View, Label: View>: View {
  let primaryAction: () -> Void
  let width: ToolbarControlWidth?
  @ViewBuilder let icon: () -> Icon
  @ViewBuilder let label: () -> Label
  private let menu: (() -> MenuContent)?

  init(
    primaryAction: @escaping () -> Void,
    width: ToolbarControlWidth? = nil,
    @ViewBuilder icon: @escaping () -> Icon,
    @ViewBuilder label: @escaping () -> Label,
    @ViewBuilder menu: @escaping () -> MenuContent
  ) {
    self.primaryAction = primaryAction
    self.width = width
    self.icon = icon
    self.label = label
    self.menu = menu
  }

  var body: some View {
    if let menu {
      Menu {
        menu()
      } label: {
        ToolbarControlLabel(width: width, icon: icon, label: label)
      } primaryAction: {
        primaryAction()
      }
    } else {
      Button(action: primaryAction) {
        ToolbarControlLabel(width: width, icon: icon, label: label)
      }
    }
  }
}

extension ToolbarControlButton where MenuContent == EmptyView {
  init(
    primaryAction: @escaping () -> Void,
    width: ToolbarControlWidth? = nil,
    @ViewBuilder icon: @escaping () -> Icon,
    @ViewBuilder label: @escaping () -> Label
  ) {
    self.primaryAction = primaryAction
    self.width = width
    self.icon = icon
    self.label = label
    self.menu = nil
  }
}

private struct ToolbarControlLabel<Icon: View, Label: View>: View {
  let width: ToolbarControlWidth?
  @ViewBuilder let icon: () -> Icon
  @ViewBuilder let label: () -> Label

  var body: some View {
    HStack(spacing: AppChromeMetrics.Toolbar.contentSpacing) {
      icon()
        .frame(width: AppChromeMetrics.Toolbar.iconSize, height: AppChromeMetrics.Toolbar.iconSize)
        .accessibilityHidden(true)
      label()
        .lineLimit(1)
        .minimumScaleFactor(0.9)
        .layoutPriority(1)
    }
    .font(.callout.weight(.semibold))
    .frame(
      minWidth: width?.min,
      idealWidth: width?.ideal,
      maxWidth: width?.max,
      minHeight: AppChromeMetrics.Toolbar.controlHeight,
      alignment: .leading
    )
  }
}

/// Shared "Dynamic-Island-style" capsule chrome for pill-shaped toolbar
/// controls (status island, notifications button, home button). Native
/// toolbar `Menu` items (the open-in-editor and script menus) get their pill
/// look for free from AppKit's own toolbar-item material, but that material
/// only tracks system light/dark — it has no way to reflect prjct's actual
/// terminal theme. So these controls draw their own capsule instead, filled
/// with the real terminal background color (`surfaceChromeAppearance`) using
/// the same fill+glassEffect pattern as `SidebarCardView`.
struct ToolbarGlassCapsuleButton<Label: View>: View {
  @Environment(\.surfaceChromeAppearance) private var chromeAppearance
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
        .padding(.horizontal, AppChromeMetrics.Toolbar.horizontalPadding)
        .padding(.vertical, AppChromeMetrics.Toolbar.verticalPadding)
        .frame(minHeight: AppChromeMetrics.Toolbar.controlHeight)
    }
    .buttonStyle(.plain)
    .background(
      chromeAppearance.backgroundColor.opacity(0.55),
      in: RoundedRectangle(cornerRadius: AppDesign.Radius.toolbar, style: .continuous)
    )
    .glassEffect(
      .regular, in: RoundedRectangle(cornerRadius: AppDesign.Radius.toolbar, style: .continuous))
  }
}
