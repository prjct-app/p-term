import ComposableArchitecture
import PTermSettingsShared
import Sharing
import SwiftUI

/// First-run / empty detail: one clear job ("open a workspace"), liquid-glass
/// card, primary CTA first. Secondary paths stay available without competing.
struct EmptyStateView: View {
  let store: StoreOf<RepositoriesFeature>
  @Shared(.settingsFile) private var settingsFile
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false

  var body: some View {
    let openRepo = AppShortcuts.openRepository.effective(from: settingsFile.global.shortcutOverrides)

    VStack(spacing: 0) {
      Spacer(minLength: 24)

      VStack(alignment: .leading, spacing: AppDesign.Spacing.hero) {
        AppIconContainer(prominent: true) {
          Image(systemName: "square.stack.3d.up.fill")
            .symbolRenderingMode(.hierarchical)
            .accessibilityHidden(true)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("All your terminals, one place")
            .font(AppTypography.title2.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

          Text(
            """
            Open a project as a workspace, run shells and coding agents side by side, \
            and keep git branch status in view — without living in chat.
            """
          )
          .font(AppTypography.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 10) {
          AppPrimaryButton(
            title: "Open Workspace or Folder",
            systemImage: "folder.badge.plus"
          ) {
            store.send(.setOpenPanelPresented(true))
          }
          .appKeyboardShortcut(openRepo)
          .help("Open Workspace or Folder (\(openRepo?.display ?? "none"))")
          .keyboardShortcutHint(openRepo?.display)

          Button {
            store.send(.requestAddRemoteRepository)
          } label: {
            Label("Add Remote over SSH…", systemImage: "network")
              .font(AppTypography.callout.weight(.medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .help("Add a workspace or folder on an SSH host")

          Button {
            store.send(.requestCloneRepository)
          } label: {
            Label("Clone a repository…", systemImage: "square.and.arrow.down.on.square")
              .font(AppTypography.callout.weight(.medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .help("Clone a remote repository into a local folder")
        }
        .padding(.top, 4)
      }
      .padding(AppDesign.Padding.card)
      .frame(maxWidth: 440, alignment: .leading)
      .appGlassSurface(.card)
      .opacity(appeared ? 1 : 0)
      .offset(y: appeared ? 0 : 12)
      .animation(
        reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.88),
        value: appeared
      )

      Spacer(minLength: 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear { appeared = true }
  }
}

private extension View {
  /// Subtle keyboard-hint caption under the primary CTA when a shortcut exists.
  @ViewBuilder
  func keyboardShortcutHint(_ display: String?) -> some View {
    if let display, !display.isEmpty {
      self.overlay(alignment: .bottomTrailing) {
        Text(display)
          .font(AppTypography.caption2.weight(.medium))
          .foregroundStyle(.tertiary)
          .padding(.trailing, 14)
          .padding(.bottom, 8)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    } else {
      self
    }
  }
}
