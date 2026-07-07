import AppKit
import SwiftUI

enum GitDiffNativePaneFactory {
  static func make(worktreeURL: URL) -> GenericNativePane {
    let hostedView = NSHostingView(rootView: GitDiffPanelView(worktreeURL: worktreeURL))
    return GenericNativePane(kind: .gitDiff, hostedView: hostedView)
  }
}
