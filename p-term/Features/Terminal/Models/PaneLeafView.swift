import AppKit

/// A split-tree leaf: either a Ghostty terminal surface or a native SwiftUI
/// pane (Agent Fleet, Git Diff, …). This is the concrete `ViewType` for
/// `SplitTree<PaneLeafView>` — see that file's doc comment for why a union
/// class (not an enum, not a protocol) is the only type that can satisfy
/// `NSView & Identifiable` for two different concrete leaf contents.
///
/// `id` mirrors the wrapped terminal's `surfaceID` for `.terminal` content,
/// so every existing surfaceID-keyed lookup (drag payloads, layout
/// snapshots, notifications, agent presence) keeps working unmodified with
/// zero migration. Native panes mint their own stable id at creation.
///
/// This object is deliberately NEVER mounted in the real view hierarchy —
/// it's a bookkeeping wrapper the split tree moves around by reference.
/// Rendering (`TerminalSplitTreeView.LeafView` / `NativePaneLeafView`) mounts
/// the WRAPPED content view directly, exactly like terminal leaves worked
/// before this type existed (a `GhosttySurfaceView` gets embedded in a
/// `GhosttySurfaceScrollView` at render time; this wrapper never sits between
/// them). `bounds` proxies through to whichever concrete view is really
/// mounted, so the two things `SplitTree` needs the leaf's `NSView`-ness for
/// — `viewBounds()`'s pixel-resize math, and the AX container's pane list —
/// keep reading the pane's real on-screen size/identity.
final class PaneLeafView: NSView, Identifiable {
  enum Content {
    case terminal(GhosttySurfaceView)
    case native(any NativePane)
  }

  let id: UUID
  let content: Content

  init(terminal surface: GhosttySurfaceView) {
    id = surface.id
    content = .terminal(surface)
    super.init(frame: .zero)
  }

  init(native pane: any NativePane) {
    id = pane.id
    content = .native(pane)
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var bounds: NSRect {
    get {
      switch content {
      case .terminal(let surface): surface.bounds
      case .native(let pane): pane.hostedView.bounds
      }
    }
    set { super.bounds = newValue }
  }
}

extension PaneLeafView {
  /// `nil` for a native leaf. Every call site that reaches into
  /// Ghostty-specific state (git branch, zmx, progress, occlusion) should
  /// guard on this instead of force-unwrapping — natives simply don't
  /// participate in those terminal-only concerns.
  var terminalSurface: GhosttySurfaceView? {
    if case .terminal(let surface) = content { surface } else { nil }
  }
}
