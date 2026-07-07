import AppKit
import SwiftUI

enum GitDiffNativePaneFactory {
  static func make(worktreeURL: URL, sourcePaneID: UUID) -> GenericNativePane {
    let hostedView = NSHostingView(
      rootView: GitDiffPanelView(worktreeURL: worktreeURL, sourcePaneID: sourcePaneID)
    )
    return GenericNativePane(kind: .gitDiff, sourcePaneID: sourcePaneID, hostedView: hostedView)
  }
}
