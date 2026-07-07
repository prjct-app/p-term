#if DEBUG
  import GhosttyKit
  import SwiftUI

  /// C0 spike (see the agentic-DX roadmap plan): can 8–12 live Ghostty
  /// (Metal/IOSurface) terminal surfaces scroll horizontally at full frame
  /// rate with momentum + snap, and cleanly suspend/resume via occlusion
  /// when off-screen? This is NOT product code — it's a throwaway harness
  /// for a human to run and measure fps/artifacts/memory in, to decide
  /// go/no-go on the Niri-style "paper" layout (Phase 5 of the plan).
  ///
  /// Go/no-go criteria (measure by eye + Activity Monitor while running):
  ///  - ≥60fps (120 on ProMotion) during momentum scroll with streaming columns
  ///  - no stale/black frames during scroll or after snap
  ///  - an off-screen column resumes rendering promptly when scrolled back
  ///  - keyboard focus / Cmd-arrow behavior stays sane with focus off-screen
  ///  - memory stable over ~10 minutes of scrolling
  struct PaperLayoutSpikeView: View {
    let runtime: GhosttyRuntime
    @State private var columns: [SpikeColumn] = []
    @State private var visibleRect: CGRect = .zero

    private static let columnCount = 12
    private static let columnWidth: CGFloat = 420
    private static let columnSpacing: CGFloat = 12
    /// Every other column runs `yes` continuously to simulate a busy agent
    /// pane — the stress case that matters (idle panes are cheap to scroll).
    private static let streamingColumnStride = 2

    var body: some View {
      ScrollView(.horizontal) {
        LazyHStack(spacing: Self.columnSpacing) {
          ForEach(columns) { column in
            VStack(spacing: 0) {
              Text(column.isStreaming ? "streaming" : "idle")
                .font(.caption)
                .foregroundStyle(.secondary)
              GhosttyTerminalView(surfaceView: column.surface)
            }
            .frame(width: Self.columnWidth)
            .id(column.id)
          }
        }
        .scrollTargetLayout()
        .padding(.horizontal, Self.columnSpacing)
      }
      .scrollTargetBehavior(.viewAligned)
      .onScrollGeometryChange(for: CGRect.self) { geometry in
        geometry.visibleRect
      } action: { _, newValue in
        visibleRect = newValue
        updateOcclusion()
      }
      .navigationTitle("Paper Layout Spike (\(columns.count) surfaces)")
      .task {
        guard columns.isEmpty else { return }
        columns = (0..<Self.columnCount).map(makeColumn)
        updateOcclusion()
      }
      .onDisappear {
        for column in columns {
          column.surface.closeSurface()
        }
        columns = []
      }
    }

    private func makeColumn(index: Int) -> SpikeColumn {
      let streaming = index.isMultiple(of: Self.streamingColumnStride)
      let surface = GhosttySurfaceView(
        id: UUID(),
        runtime: runtime,
        workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
        command: streaming ? "/usr/bin/yes" : nil,
        context: GHOSTTY_SURFACE_CONTEXT_TAB
      )
      return SpikeColumn(id: surface.id, surface: surface, isStreaming: streaming)
    }

    /// Suspend rendering for columns fully outside the visible rect ± one
    /// column width. Mirrors `WorktreeTerminalState.applySurfaceActivity`'s
    /// `setOcclusion` gate — the exact mechanism Phase 5 (C1) would reuse for
    /// real. Column x-offsets are approximate (leading padding not modeled
    /// precisely) — fine for a feel/fps spike, not meant to be pixel-exact.
    private func updateOcclusion() {
      guard !columns.isEmpty, visibleRect != .zero else { return }
      let expanded = visibleRect.insetBy(dx: -Self.columnWidth, dy: 0)
      let stride = Self.columnWidth + Self.columnSpacing
      for (index, column) in columns.enumerated() {
        let columnRect = CGRect(x: CGFloat(index) * stride, y: 0, width: Self.columnWidth, height: 1)
        column.surface.setOcclusion(expanded.intersects(columnRect))
      }
    }

    private struct SpikeColumn: Identifiable {
      let id: UUID
      let surface: GhosttySurfaceView
      let isStreaming: Bool
    }
  }

  /// Debug-menu entry point (Window menu → "Paper Layout Spike"). Mirrors
  /// `OpenActivityFeedButton`'s bare `openWindow(id:)` pattern.
  struct OpenPaperLayoutSpikeButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
      Button("Paper Layout Spike") { openWindow(id: WindowID.paperLayoutSpike) }
        .help("C0 spike: scrollable Ghostty surfaces, for measuring paper-layout feel/fps")
    }
  }
#endif
