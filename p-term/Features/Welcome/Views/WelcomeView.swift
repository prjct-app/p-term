import AppKit
import ComposableArchitecture
import PTermSettingsShared
import Sharing
import SwiftUI

/// Full-screen home view shown in place of the sidebar+detail split while
/// `AppFeature.State.isShowingWelcomeScreen` is true.
struct WelcomeView: View {
  let repositoriesStore: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager
  @Environment(\.colorScheme) private var systemColorScheme
  @Shared(.settingsFile) private var settingsFile
  @State private var headline = WelcomePromptCopy.headlines.randomElement()!
  @State private var configReloadCounter = 0

  private var activeWorktrees: [Worktree] {
    terminalManager.activeWorktreeIDs
      .compactMap { repositoriesStore.state.worktree(for: $0) }
      .sorted { $0.name < $1.name }
  }

  private var resolvedColorScheme: ColorScheme {
    _ = configReloadCounter
    _ = systemColorScheme
    return terminalManager.surfaceBackgroundColorScheme()
  }

  private var backgroundColor: NSColor {
    _ = configReloadCounter
    return terminalManager.surfaceBackgroundColor()
  }

  var body: some View {
    let openRepo = AppShortcuts.openRepository.effective(from: settingsFile.global.shortcutOverrides)

    ZStack {
      WelcomeLiquidBackground(
        colorScheme: resolvedColorScheme,
        backgroundColor: backgroundColor
      )

      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 8) {
          Image("pterm-wordmark")
            .resizable()
            .scaledToFit()
            .frame(width: AppDesign.Welcome.logoWidth)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 6) {
            Text(headline)
              .font(AppTypography.title2.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
              .minimumScaleFactor(0.82)
              .fixedSize(horizontal: false, vertical: true)

            Text("Open a repository or continue an active terminal.")
              .font(AppTypography.callout)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        WelcomeOpenAction(openShortcut: openRepo) {
          repositoriesStore.send(.setOpenPanelPresented(true))
        }

        WelcomeSessionsSection(
          activeWorktrees: activeWorktrees,
          selectWorktree: { worktree in
            repositoriesStore.send(.selectWorktree(worktree.id, focusTerminal: true))
          }
        )
      }
      .frame(width: AppDesign.Welcome.contentWidth, alignment: .leading)
      .padding(.horizontal, AppDesign.Welcome.contentPadding)
      .padding(.vertical, AppDesign.Welcome.verticalPadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .environment(\.colorScheme, resolvedColorScheme)
    .toolbar(.hidden, for: .windowToolbar)
    .onReceive(NotificationCenter.default.publisher(for: .ghosttyRuntimeConfigDidChange)) { _ in
      configReloadCounter &+= 1
    }
  }
}

private enum WelcomePromptCopy {
  static let headlines = [
    "What can I take off your plate?",
    "Where should we continue?",
    "What needs a terminal?",
    "Which workspace should open?",
    "Where do you want to start?",
    "What needs to be checked?",
    "Which repo are you working in?",
    "What should be ready first?",
    "Where should the terminal land?",
    "Which session should resume?",
    "What needs a clean shell?",
    "Which build are we checking?",
    "Where should p/term open?",
    "What should come back into view?",
    "Which folder needs attention?",
    "What needs to run next?",
    "Which terminal should resume?",
    "Where should the work continue?",
    "What needs to be debugged?",
    "Which repo should lead?"
  ]
}

private struct WelcomeOpenAction: View {
  let openShortcut: AppShortcut?
  let openRepository: () -> Void

  var body: some View {
    AppActionRow(
      title: "Open Repository or Folder",
      subtitle: openShortcut?.display ?? AppShortcuts.openRepository.display,
      action: openRepository
    ) {
      AppIconContainer {
        Image(systemName: "folder.badge.plus")
      }
    }
    .appKeyboardShortcut(openShortcut)
    .help("Open Repository or Folder (\(openShortcut?.display ?? "none"))")
  }
}

private struct WelcomeSessionsSection: View {
  let activeWorktrees: [Worktree]
  let selectWorktree: (Worktree) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AppDesign.Spacing.sectionHeader) {
      AppSectionHeader(title: "Active terminals")

      if activeWorktrees.isEmpty {
        WelcomeEmptyTerminalRow()
      } else {
        VStack(spacing: AppChromeMetrics.Welcome.rowSpacing) {
          ForEach(activeWorktrees) { worktree in
            WelcomeActiveTerminalRow(worktree: worktree) {
              selectWorktree(worktree)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct WelcomeActiveTerminalRow: View {
  let worktree: Worktree
  let action: () -> Void

  var body: some View {
    AppActionRow(
      title: worktree.name,
      subtitle: worktree.repositoryRootURL.lastPathComponent,
      action: action
    ) {
      AppIconContainer {
        Image(systemName: "terminal.fill")
      }
    }
  }
}

private struct WelcomeEmptyTerminalRow: View {
  var body: some View {
    HStack(spacing: AppDesign.Spacing.rowContent) {
      AppIconContainer {
        Image(systemName: "terminal")
      }

      VStack(alignment: .leading, spacing: 2) {
        Text("No active terminals")
          .font(AppTypography.body.weight(.semibold))
        Text("Open a repository to start one.")
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

private struct WelcomeLiquidBackground: View {
  let colorScheme: ColorScheme
  let backgroundColor: NSColor

  var body: some View {
    ZStack {
      Color(nsColor: backgroundColor)

      WelcomeAnimatedPixelField(colorScheme: colorScheme)
    }
      .ignoresSafeArea()
      .allowsHitTesting(false)
  }
}

private struct WelcomeAnimatedPixelField: View {
  let colorScheme: ColorScheme

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
      Canvas { context, size in
        let time = timeline.date.timeIntervalSinceReferenceDate
        let isDark = colorScheme == .dark
        let primary = isDark ? Color.white : Color.black
        let spacing: CGFloat = 16
        let dot: CGFloat = 2
        let columns = Int(size.width / spacing) + 4
        let rows = Int(size.height / spacing) + 4
        let driftX = CGFloat(sin(time * 0.20)) * 18
        let driftY = CGFloat(cos(time * 0.16)) * 14
        let focusA = CGPoint(x: size.width * 0.30 + driftX, y: size.height * 0.31 + driftY)
        let focusB = CGPoint(x: size.width * 0.78 - driftX * 0.7, y: size.height * 0.78 - driftY)
        let focusC = CGPoint(x: size.width * 0.60 + driftX * 0.35, y: size.height * 0.18)

        for row in 0..<rows {
          for column in 0..<columns {
            let stagger = CGFloat(row % 2) * spacing * 0.5
            let x = CGFloat(column - 1) * spacing + stagger + CGFloat(sin(time * 0.12 + Double(row) * 0.25)) * 2.8
            let y = CGFloat(row - 1) * spacing + CGFloat(cos(time * 0.10 + Double(column) * 0.18)) * 2.2
            let point = CGPoint(x: x, y: y)

            let a = Self.influence(point, center: focusA, radius: 390)
            let b = Self.influence(point, center: focusB, radius: 460)
            let c = Self.influence(point, center: focusC, radius: 280)
            let wave = 0.5 + 0.5 * sin(time * 0.75 + Double(column) * 0.26 + Double(row) * 0.17)
            let influence = max(max(a, b), c)
            let opacity = influence * ((isDark ? 0.12 : 0.070) + (isDark ? 0.11 : 0.075) * wave)
            guard opacity > 0.012 else { continue }

            let scale = 0.78 + CGFloat(wave) * 0.58
            let rect = CGRect(x: x, y: y, width: dot * scale, height: dot * scale)
            context.fill(
              Path(roundedRect: rect, cornerRadius: 0.8),
              with: .color(primary.opacity(opacity))
            )
          }
        }
      }
    }
    .blendMode(colorScheme == .dark ? .plusLighter : .multiply)
    .opacity(colorScheme == .dark ? 0.95 : 0.70)
  }

  private static func influence(_ point: CGPoint, center: CGPoint, radius: CGFloat) -> Double {
    let dx = point.x - center.x
    let dy = point.y - center.y
    let distance = sqrt(dx * dx + dy * dy)
    let normalized = max(0, 1 - distance / radius)
    return Double(normalized * normalized)
  }
}
