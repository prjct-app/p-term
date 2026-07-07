import SwiftUI

/// Compatibility wrapper for the native split-tree Git diff pane. The real
/// feature now lives in `GitDiffPanelView`, which owns structured diff state
/// and panel tools.
struct GitDiffPaneView: View {
  let worktreeURL: URL

  var body: some View {
    GitDiffPanelView(worktreeURL: worktreeURL)
  }
}
