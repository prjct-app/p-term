import PTermSettingsShared
import SwiftUI

struct EmptyTerminalPaneView: View {
  let message: String
  var actionTitle: String?
  var action: (() -> Void)?
  @Environment(\.surfaceChromeAppearance) private var chromeAppearance
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false

  var body: some View {
    ZStack {
      chromeAppearance.backgroundColor
        .ignoresSafeArea()

      EmptyTerminalPixelField(colorScheme: chromeAppearance.colorScheme, reduceMotion: reduceMotion)

      VStack(alignment: .leading, spacing: 20) {
        header

        if let actionTitle, let action {
          AppActionRow(
            title: actionTitle,
            subtitle: "Open a shell in this workspace",
            action: action
          ) {
            AppIconContainer {
              Image(systemName: "plus.rectangle.on.folder")
                .accessibilityHidden(true)
            }
          }
          .help(actionTitle)
        }

        VStack(alignment: .leading, spacing: AppDesign.Spacing.sectionHeader) {
          AppSectionHeader(title: "Status")

          HStack(spacing: AppDesign.Spacing.rowContent) {
            AppIconContainer {
              Image(systemName: "apple.terminal")
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
              Text(message)
                .font(AppTypography.body.weight(.semibold))
              Text("No shell is attached yet. Start one to run agents here.")
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
          }
          .padding(.horizontal, AppDesign.Padding.rowHorizontal)
          .padding(.vertical, AppDesign.Padding.rowVertical)
          .frame(maxWidth: .infinity, minHeight: AppDesign.Size.rowMinHeight, alignment: .leading)
          .appRowSurface()
        }
      }
      .frame(maxWidth: 480, alignment: .leading)
      .padding(.horizontal, 48)
      .padding(.vertical, 44)
      .opacity(appeared ? 1 : 0)
      .offset(y: appeared ? 0 : 10)
      .animation(
        reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86), value: appeared
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .environment(\.colorScheme, chromeAppearance.colorScheme)
    .onAppear {
      appeared = true
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("prjct")
        .font(.system(size: 36, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
        .accessibilityLabel("prjct")

      VStack(alignment: .leading, spacing: 6) {
        Text("Ready for a terminal")
          .font(AppTypography.title3.weight(.semibold))
          .foregroundStyle(.primary)
        Text(
          """
          This workspace is a home for terminals and agents. Git branch status stays \
          visible — the product is the terminal, not git.
          """
        )
        .font(AppTypography.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct EmptyTerminalPixelField: View {
  let colorScheme: ColorScheme
  let reduceMotion: Bool

  var body: some View {
    Group {
      if reduceMotion {
        pixelField(time: 0)
      } else {
        TimelineView(.animation(minimumInterval: 1 / 15)) { timeline in
          pixelField(time: timeline.date.timeIntervalSinceReferenceDate)
        }
      }
    }
    .blendMode(colorScheme == .dark ? .plusLighter : .multiply)
    .opacity(colorScheme == .dark ? 0.95 : 0.70)
    .drawingGroup()
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func pixelField(time: TimeInterval) -> some View {
    Canvas { context, size in
      let isDark = colorScheme == .dark
      let primary = isDark ? Color.white : Color.black
      let spacing: CGFloat = 16
      let dot: CGFloat = 2
      let columns = Int(size.width / spacing) + 4
      let rows = Int(size.height / spacing) + 4
      let driftX = CGFloat(sin(time * 0.20)) * 18
      let driftY = CGFloat(cos(time * 0.16)) * 14
      let focusA = CGPoint(x: size.width * 0.34 + driftX, y: size.height * 0.35 + driftY)
      let focusB = CGPoint(x: size.width * 0.74 - driftX * 0.7, y: size.height * 0.72 - driftY)
      let focusC = CGPoint(x: size.width * 0.58 + driftX * 0.35, y: size.height * 0.18)

      for row in 0..<rows {
        for column in 0..<columns {
          let stagger = CGFloat(row % 2) * spacing * 0.5
          let originX =
            CGFloat(column - 1) * spacing + stagger
            + CGFloat(sin(time * 0.12 + Double(row) * 0.25)) * 2.8
          let originY =
            CGFloat(row - 1) * spacing
            + CGFloat(cos(time * 0.10 + Double(column) * 0.18)) * 2.2
          let point = CGPoint(x: originX, y: originY)

          let influence = max(
            Self.influence(point, center: focusA, radius: 390),
            max(
              Self.influence(point, center: focusB, radius: 460),
              Self.influence(point, center: focusC, radius: 280)
            )
          )
          let wave = 0.5 + 0.5 * sin(time * 0.75 + Double(column) * 0.26 + Double(row) * 0.17)
          let opacity = influence * ((isDark ? 0.12 : 0.07) + (isDark ? 0.11 : 0.075) * wave)
          guard opacity > 0.012 else { continue }

          let scale = 0.78 + CGFloat(wave) * 0.58
          let rect = CGRect(x: originX, y: originY, width: dot * scale, height: dot * scale)
          context.fill(
            Path(roundedRect: rect, cornerRadius: 0.8),
            with: .color(primary.opacity(opacity))
          )
        }
      }
    }
  }

  private static func influence(_ point: CGPoint, center: CGPoint, radius: CGFloat) -> Double {
    let deltaX = point.x - center.x
    let deltaY = point.y - center.y
    let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
    let normalized = max(0, 1 - distance / radius)
    return Double(normalized * normalized)
  }
}
