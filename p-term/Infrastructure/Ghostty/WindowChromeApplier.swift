import AppKit
import GhosttyKit
import SwiftUI

struct WindowAppearanceState: Equatable {
  let opacity: Double
  let appearance: NSAppearance.Name?
  let isFullScreen: Bool
  let isOpaqueOverride: Bool
}

@MainActor
enum WindowChromeApplier {
  // Each observer site owns its own `lastApplied` so they don't fight.
  static func apply(
    window: NSWindow,
    runtime: GhosttyRuntime,
    lastApplied: inout WindowAppearanceState?
  ) {
    guard window.isVisible else { return }
    let opacity = runtime.backgroundOpacity()
    let next = WindowAppearanceState(
      opacity: opacity,
      appearance: window.effectiveAppearance.name,
      isFullScreen: window.styleMask.contains(.fullScreen),
      isOpaqueOverride: runtime.isBackgroundOpaque
    )
    if next == lastApplied {
      return
    }
    lastApplied = next
    window.effectiveAppearance.performAsCurrentDrawingAppearance {
      let resolvedColor = runtime.backgroundColor()
      if !next.isFullScreen, opacity < 1, !next.isOpaqueOverride {
        window.isOpaque = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = resolvedColor.withAlphaComponent(opacity)
        if let app = runtime.app {
          ghostty_set_window_background_blur(
            app,
            Unmanaged.passUnretained(window).toOpaque()
          )
        }
        return
      }
      window.isOpaque = true
      window.titlebarAppearsTransparent = !next.isFullScreen
      window.backgroundColor = resolvedColor
    }
  }
}

// Mounted at the ContentView root so window background re-applies on
// appearance / fullscreen / config changes even when no Ghostty surface is
// currently displayed (Empty / Loading / Archived / Multi-select states).
struct WindowChromeObserver: NSViewRepresentable {
  let runtime: GhosttyRuntime
  var trailingTitlebarReservationWidth: CGFloat = 0

  func makeNSView(context: Context) -> WindowChromeObserverNSView {
    WindowChromeObserverNSView(runtime: runtime)
  }

  func updateNSView(_ nsView: WindowChromeObserverNSView, context: Context) {
    nsView.trailingTitlebarReservationWidth = trailingTitlebarReservationWidth
  }
}

/// Invisible titlebar occupant. Installed at `.right` it shrinks the space
/// NSToolbar lays items into, so trailing toolbar pills land left of the
/// right side panel instead of floating over it. Draws nothing and swallows
/// no clicks — the titlebar under it still drags the window.
private final class TitlebarTrailingReservationView: NSView {
  var width: CGFloat {
    didSet {
      guard width != oldValue else { return }
      invalidateIntrinsicContentSize()
      setFrameSize(NSSize(width: width, height: frame.height))
    }
  }

  init(width: CGFloat) {
    self.width = width
    super.init(frame: NSRect(x: 0, y: 0, width: width, height: 1))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override var intrinsicContentSize: NSSize {
    NSSize(width: width, height: 1)
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class WindowChromeObserverNSView: NSView {
  private let runtime: GhosttyRuntime
  private var lastApplied: WindowAppearanceState?
  private var trailingAccessory: NSTitlebarAccessoryViewController?
  private var trailingReservationView: TitlebarTrailingReservationView?
  private weak var trailingAccessoryWindow: NSWindow?

  var trailingTitlebarReservationWidth: CGFloat = 0 {
    didSet {
      guard trailingTitlebarReservationWidth != oldValue else { return }
      applyTrailingReservation()
    }
  }
  // `nonisolated(unsafe)` so `deinit` (Swift 6 nonisolated by default for
  // @MainActor classes) can release the tokens; NotificationCenter is itself
  // thread-safe, and only main-actor methods otherwise mutate the array.
  private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

  init(runtime: GhosttyRuntime) {
    self.runtime = runtime
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  deinit {
    let center = NotificationCenter.default
    for observer in observers {
      center.removeObserver(observer)
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    clearObservers()
    guard let window else {
      removeTrailingReservation()
      return
    }
    addObservers(for: window)
    apply()
    applyTrailingReservation()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    apply()
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  private func apply() {
    guard let window else { return }
    WindowChromeApplier.apply(window: window, runtime: runtime, lastApplied: &lastApplied)
  }

  /// Keeps exactly one transparent `.right` titlebar accessory sized to the
  /// visible right panel (none when the panel is closed). This is the
  /// window-level counterpart of the panel column in ContentView — a SwiftUI
  /// ToolbarItem spacer would render as a visible glass pill.
  private func applyTrailingReservation() {
    guard let window else { return }
    let width = trailingTitlebarReservationWidth

    guard width > 0 else {
      removeTrailingReservation()
      return
    }

    if let trailingReservationView, trailingAccessory != nil, trailingAccessoryWindow === window {
      trailingReservationView.width = width
      return
    }

    removeTrailingReservation()
    let view = TitlebarTrailingReservationView(width: width)
    let accessory = NSTitlebarAccessoryViewController()
    accessory.view = view
    accessory.layoutAttribute = .right
    window.addTitlebarAccessoryViewController(accessory)
    trailingAccessory = accessory
    trailingReservationView = view
    trailingAccessoryWindow = window
  }

  private func removeTrailingReservation() {
    trailingAccessory?.removeFromParent()
    trailingAccessory = nil
    trailingReservationView = nil
    trailingAccessoryWindow = nil
  }

  private func addObservers(for window: NSWindow) {
    let center = NotificationCenter.default
    let windowNotifications: [Notification.Name] = [
      NSWindow.didEnterFullScreenNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didChangeOcclusionStateNotification,
      NSWindow.didChangeScreenNotification,
    ]
    for name in windowNotifications {
      observers.append(
        center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
          Task { @MainActor [weak self] in self?.apply() }
        }
      )
    }
    observers.append(
      center.addObserver(
        forName: .ghosttyRuntimeConfigDidChange,
        object: runtime,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.lastApplied = nil
          self?.apply()
        }
      }
    )
  }

  private func clearObservers() {
    let center = NotificationCenter.default
    for observer in observers {
      center.removeObserver(observer)
    }
    observers.removeAll()
  }
}
