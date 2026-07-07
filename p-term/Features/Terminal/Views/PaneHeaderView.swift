import AppKit
import SwiftUI

/// Shared per-pane header — used by BOTH tiled (`TerminalSplitTreeView.LeafView`
/// / `NativePaneLeafView`) and paper (`PaperLayoutView`) panes so the same
/// actions are available regardless of which layout mode a tab is in. Drag
/// reordering works differently in each mode (tiled panes drag/drop onto each
/// other via `NSItemProvider`; paper columns drag via a plain `DragGesture`
/// with tracked frames), so the drag affordance itself is a slot the caller
/// fills in rather than something this view knows how to do.
struct PaneHeaderView<DragHandle: View>: View {
  let title: String
  let isActive: Bool
  let onClose: () -> Void
  /// `nil` hides "Split with Git Diff" from the menu (no worktree context to
  /// build the pane from — shouldn't happen in practice, but a pane leaf
  /// created via some future path might not have one).
  let onInsertGitDiffPane: (() -> Void)?
  @ViewBuilder let dragHandle: () -> DragHandle

  @State private var isHoveringBar = false
  @State private var isHoveringClose = false
  @State private var isHoveringMenu = false
  @State private var isPressingClose = false

  static var height: CGFloat { 24 }

  var body: some View {
    HStack(spacing: 6) {
      dragHandle()

      Image(systemName: "apple.terminal")
        .font(.caption2)
        .foregroundStyle(.secondary)

      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Spacer(minLength: 0)

      // Filled when this is the focused pane, hollow otherwise — same
      // active/inactive dot language the left sidebar's session rows use.
      Circle()
        .fill(isActive ? Color.primary : Color.secondary.opacity(0.35))
        .frame(width: 6, height: 6)

      if let onInsertGitDiffPane {
        Menu {
          Button("Split with Git Diff", action: onInsertGitDiffPane)
        } label: {
          Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 16)
        .background(Color.primary.opacity(isHoveringMenu ? 0.15 : 0), in: .circle)
        .onHover { isHoveringMenu = $0 }
        .opacity(isHoveringBar || isHoveringMenu ? 1 : 0)
        .help("Split with Git Diff")
      }

      Button("Close Terminal", systemImage: "xmark") {
        onClose()
      }
      .labelStyle(.iconOnly)
      .buttonStyle(TerminalPressTrackingButtonStyle(isPressed: $isPressingClose))
      .font(.system(size: 9, weight: .bold))
      .foregroundStyle(.secondary)
      .frame(width: 16, height: 16)
      .background(Color.primary.opacity(isHoveringClose ? 0.15 : 0), in: .circle)
      .contentShape(.circle)
      .onHover { isHoveringClose = $0 }
      .opacity(isHoveringBar || isHoveringClose ? 1 : 0)
      .help("Close Terminal")
    }
    .padding(.horizontal, 8)
    .frame(height: Self.height)
    .frame(maxWidth: .infinity)
    .contentShape(.rect)
    .onHover { hovering in
      guard hovering != isHoveringBar else { return }
      isHoveringBar = hovering
    }
  }
}
