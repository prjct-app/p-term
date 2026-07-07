import AppKit

/// Identifies what a native (non-terminal) split-tree leaf renders. Extend as
/// more native pane types ship.
enum NativePaneKind: Equatable, Sendable {
  case agentFleet
  case gitDiff

  var displayTitle: String {
    switch self {
    case .agentFleet: "Agent Fleet"
    case .gitDiff: "Git Diff"
    }
  }
}

/// A non-terminal split-tree leaf's content. `WorktreeTerminalState` only
/// ever stores and moves these around by reference/id — it never constructs
/// the SwiftUI content itself (that needs app-level store access this
/// terminal-layer class deliberately doesn't have). Callers one layer up
/// (AppFeature / views) build `hostedView` and hand it down already-formed.
protocol NativePane: AnyObject {
  var id: UUID { get }
  var kind: NativePaneKind { get }
  /// The real, already-constructed content view (typically an
  /// `NSHostingView`). `PaneLeafView` mounts this as a full-bleed subview.
  var hostedView: NSView { get }
}

/// Default `NativePane` — a fixed id/kind/view triple. Sufficient for every
/// native pane today; a pane needing its own extra bookkeeping can define a
/// dedicated conforming type instead of extending this one.
final class GenericNativePane: NativePane {
  let id: UUID
  let kind: NativePaneKind
  let hostedView: NSView

  init(id: UUID = UUID(), kind: NativePaneKind, hostedView: NSView) {
    self.id = id
    self.kind = kind
    self.hostedView = hostedView
  }
}
