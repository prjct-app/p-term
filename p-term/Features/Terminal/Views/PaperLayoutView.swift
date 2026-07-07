import AppKit
import SwiftUI

/// Niri-style "paper" rendering of one tab: columns scroll horizontally,
/// each a top-to-bottom stack of panes. Alternative to `TerminalSplitTreeView`
/// for tabs in `.paper` layout mode (see `WorktreeTerminalState.layoutMode`).
///
/// Built on the C0 spike's validated approach (`Terminal/Spike/PaperLayoutSpikeView.swift`):
/// `LazyHStack` + `.scrollTargetBehavior(.viewAligned)` for momentum/snap,
/// scroll-geometry-driven occlusion so off-screen panes suspend exactly like
/// `applySurfaceActivity` already does for tiled tabs.
///
/// Every pane gets its own header bar (drag handle + close button, same
/// hover-reveal idiom as `TerminalTabCloseButton`) — dragging is scoped to
/// that handle, NOT the whole pane, because making the entire content area
/// draggable made simple clicks into the terminal register as drag starts.
/// Reordering uses a plain `DragGesture` + tracked column frames — the SAME
/// pattern `TerminalTabsRowView` already uses to reorder tabs — rather than
/// `NSItemProvider`-based `.onDrag`/`.onDrop`: that API didn't reliably win
/// against `ScrollView(.horizontal)`'s own pan recognizer here, so drags
/// just… didn't start. A plain `DragGesture` is what the column resize
/// handle already used successfully in the same scroll view.
struct PaperLayoutView: View {
  let tabId: TerminalTabID
  let terminalState: WorktreeTerminalState
  let layout: PaperLayout
  let activeSurfaceID: UUID?
  let unfocusedSplitOverlay: (fill: Color?, opacity: Double)

  @State private var scrollPosition = ScrollPosition()
  @State private var draggingColumnID: UUID?
  @State private var columnFrames: [UUID: CGRect] = [:]

  var body: some View {
    ZStack(alignment: .bottom) {
      ScrollView(.horizontal) {
        LazyHStack(spacing: 0) {
          ForEach(layout.columns) { column in
            HStack(spacing: 0) {
              PaperColumnView(
                column: column,
                terminalState: terminalState,
                tabId: tabId,
                activeSurfaceID: activeSurfaceID,
                unfocusedSplitOverlay: unfocusedSplitOverlay,
                globalPaneIndex: globalPaneIndex,
                onDragChanged: { _ in
                  if draggingColumnID != column.id { draggingColumnID = column.id }
                },
                onDragEnded: { location in
                  let destination = targetColumnID(for: location.x, excluding: column.id)
                  terminalState.movePaperColumn(tabId: tabId, columnID: column.id, beforeColumnID: destination)
                  draggingColumnID = nil
                }
              )
              .frame(width: column.width)
              .opacity(draggingColumnID == column.id ? 0.4 : 1)
              .background(
                GeometryReader { proxy in
                  Color.clear
                    .onAppear { columnFrames[column.id] = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                      columnFrames[column.id] = newFrame
                    }
                }
              )

              PaperColumnResizeHandle(width: column.width) { newWidth in
                terminalState.resizePaperColumn(tabId: tabId, columnID: column.id, width: newWidth)
              }
            }
            .id(column.id)
          }
        }
        .scrollTargetLayout()
        // Half-gap leading/trailing inset so the first/last column sit the
        // same distance from the tab content area's edge as the wrapper
        // padding around it — see the doc comment on that padding in
        // `WorktreeTerminalTabsView` for why it's a HALF gap here, not a
        // full one.
        .padding(.horizontal, PaneChromeMetrics.gap / 2)
      }
      .scrollPosition($scrollPosition)
      .scrollTargetBehavior(.viewAligned)
      .onScrollGeometryChange(for: Set<UUID>.self) { geometry in
        visiblePaneIDs(in: geometry.visibleRect)
      } action: { _, newValue in
        terminalState.updatePaperViewport(tabId: tabId, visiblePaneIDs: newValue)
      }
      .onChange(of: terminalState.paperScrollRequest) { _, request in
        guard let request, request.tabId == tabId,
          let columnIndex = layout.columnIndex(containing: request.paneID)
        else { return }
        withAnimation {
          scrollPosition.scrollTo(id: layout.columns[columnIndex].id)
        }
      }

      // Position indicator: derived from the focused pane's column (not raw
      // scroll geometry) so it's exact and updates on keyboard nav even
      // between scroll-geometry ticks.
      if layout.columns.count > 1, let activeSurfaceID,
        let columnIndex = layout.columnIndex(containing: activeSurfaceID)
      {
        Text("Column \(columnIndex + 1) of \(layout.columns.count)")
          .font(.caption)
          .monospacedDigit()
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(.regularMaterial, in: Capsule())
          .padding(.bottom, 8)
          .allowsHitTesting(false)
      }
    }
  }

  /// 1-based position across the WHOLE tab, not reset per column — most
  /// columns hold exactly one pane, so per-column numbering showed "Pane 1"
  /// in every single column, indistinguishable from each other.
  private var globalPaneIndex: [UUID: Int] {
    Dictionary(
      uniqueKeysWithValues: layout.allPaneIDs.enumerated().map { index, paneID in (paneID, index + 1) }
    )
  }

  /// First column whose midpoint is to the right of `globalX`, excluding the
  /// dragged column itself — mirrors `TerminalTabsRowView.updateDropTarget`.
  /// `nil` means "past the last column," i.e. move to the end.
  private func targetColumnID(for globalX: CGFloat, excluding draggedID: UUID) -> UUID? {
    for column in layout.columns where column.id != draggedID {
      guard let frame = columnFrames[column.id] else { continue }
      if globalX < frame.midX {
        return column.id
      }
    }
    return nil
  }

  /// Column x-offsets account for each column's own width plus the 8pt gap
  /// between them — exact, since widths aren't uniform.
  private func visiblePaneIDs(in visibleRect: CGRect) -> Set<UUID> {
    guard visibleRect != .zero else { return [] }
    let expanded = visibleRect.insetBy(dx: -PaperLayout.defaultColumnWidth, dy: 0)
    var result: Set<UUID> = []
    var x: CGFloat = 0
    for column in layout.columns {
      let columnRect = CGRect(x: x, y: 0, width: column.width, height: 1)
      if expanded.intersects(columnRect) {
        result.formUnion(column.paneIDs)
      }
      x += column.width + PaneChromeMetrics.gap
    }
    return result
  }
}

private struct PaperColumnView: View {
  let column: PaperLayout.Column
  let terminalState: WorktreeTerminalState
  let tabId: TerminalTabID
  let activeSurfaceID: UUID?
  let unfocusedSplitOverlay: (fill: Color?, opacity: Double)
  let globalPaneIndex: [UUID: Int]
  let onDragChanged: (CGPoint) -> Void
  let onDragEnded: (CGPoint) -> Void

  var body: some View {
    VStack(spacing: PaneChromeMetrics.gap) {
      ForEach(column.paneIDs, id: \.self) { paneID in
        if let pane = terminalState.pane(withID: paneID, in: tabId) {
          let isActive = paneID == activeSurfaceID
          VStack(spacing: 0) {
            PaperPaneHeaderView(
              paneIndex: globalPaneIndex[paneID] ?? 0,
              isActive: isActive,
              onClose: { terminalState.closePane(id: paneID, in: tabId) },
              onInsertGitDiffPane: {
                let pane = GitDiffNativePaneFactory.make(worktreeURL: terminalState.worktreeURL)
                terminalState.insertNativePane(pane, in: tabId, anchorPaneID: paneID, direction: .right)
              },
              onDragChanged: onDragChanged,
              onDragEnded: onDragEnded
            )
            PaperPaneContentView(
              pane: pane,
              isActive: isActive,
              unfocusedSplitOverlay: unfocusedSplitOverlay
            )
          }
          // Chrome wraps header + content TOGETHER as one card — applying it
          // to the content alone left the header sitting outside the border,
          // reading as two disconnected pieces instead of a single pane.
          .paneCardChrome(isActive: isActive)
        }
      }
    }
    // Half-gap top/bottom inset, matching the leading/trailing inset on the
    // column strip — see that padding's doc comment.
    .padding(.vertical, PaneChromeMetrics.gap / 2)
  }
}

/// Paper-mode instance of the shared `PaneHeaderView` — the drag handle is a
/// plain `DragGesture` reporting column-reorder positions (see
/// `PaperLayoutView`'s doc comment for why paper can't use the same
/// `NSItemProvider` drag tiled mode uses). Dragging is scoped to this bar
/// (never the terminal content below it) — the whole-pane-is-draggable
/// version made ordinary clicks into the terminal flaky, registering as
/// drag starts instead of focus/selection. Reorders the pane's COLUMN as a
/// whole (matching `PaperLayout`'s column-granularity model); a column with
/// several stacked panes can be dragged from any of their headers.
private struct PaperPaneHeaderView: View {
  let paneIndex: Int
  let isActive: Bool
  let onClose: () -> Void
  let onInsertGitDiffPane: () -> Void
  let onDragChanged: (CGPoint) -> Void
  let onDragEnded: (CGPoint) -> Void

  @State private var isHoveringDragHandle = false

  var body: some View {
    PaneHeaderView(
      title: "Pane \(paneIndex)",
      isActive: isActive,
      onClose: onClose,
      onInsertGitDiffPane: onInsertGitDiffPane
    ) {
      Image(systemName: "line.3.horizontal")
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .contentShape(.rect)
        .onHover { hovering in
          guard hovering != isHoveringDragHandle else { return }
          isHoveringDragHandle = hovering
          if hovering {
            NSCursor.openHand.push()
          } else {
            NSCursor.pop()
          }
        }
        .onDisappear {
          if isHoveringDragHandle {
            isHoveringDragHandle = false
            NSCursor.pop()
          }
        }
        .gesture(
          DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { gesture in onDragChanged(gesture.location) }
            .onEnded { gesture in onDragEnded(gesture.location) }
        )
    }
  }
}

/// The card chrome (border/rounding) is applied by `PaperColumnView` to the
/// header+content pair TOGETHER, not here — see its doc comment.
private struct PaperPaneContentView: View {
  let pane: PaneLeafView
  let isActive: Bool
  let unfocusedSplitOverlay: (fill: Color?, opacity: Double)

  var body: some View {
    Group {
      switch pane.content {
      case .terminal(let surface):
        GhosttyTerminalView(surfaceView: surface)
      case .native(let nativePane):
        TerminalSplitTreeView.NativePaneHostView(hostedView: nativePane.hostedView)
      }
    }
    .overlay {
      if !isActive, let fill = unfocusedSplitOverlay.fill, unfocusedSplitOverlay.opacity > 0 {
        fill
          .opacity(unfocusedSplitOverlay.opacity)
          .allowsHitTesting(false)
      }
    }
  }
}

/// Column resize handle, centered inside the 8pt gap between columns. Unlike
/// tiled mode's hairline `SplitView` divider, this carries a small
/// always-visible grip capsule — paper's columns sit inside a scrollable
/// strip, so a barely-there 1px line invited exactly the "how do I even grab
/// this" complaint a pure hover-reveal divider would cause. Resize is a
/// drag-DELTA each gesture (not an absolute position), since columns live in
/// a horizontally scrolling strip where absolute x isn't stable.
private struct PaperColumnResizeHandle: View {
  let width: CGFloat
  let onResize: (CGFloat) -> Void

  @State private var isHovered = false
  @State private var dragStartWidth: CGFloat?

  var body: some View {
    ZStack {
      Capsule()
        .fill(Color(nsColor: .separatorColor))
        .opacity(isHovered ? 1 : 0.6)
        .frame(width: isHovered ? 4 : 3, height: 32)
    }
    .frame(width: PaneChromeMetrics.gap)
    .frame(maxHeight: .infinity)
    .contentShape(.rect)
    .onHover { hovering in
      guard hovering != isHovered else { return }
      isHovered = hovering
      if hovering {
        NSCursor.resizeLeftRight.push()
      } else {
        NSCursor.pop()
      }
    }
    .onDisappear {
      if isHovered {
        isHovered = false
        NSCursor.pop()
      }
    }
    .gesture(
      DragGesture()
        .onChanged { gesture in
          let base = dragStartWidth ?? width
          if dragStartWidth == nil { dragStartWidth = width }
          onResize(base + gesture.translation.width)
        }
        .onEnded { _ in dragStartWidth = nil }
    )
    .animation(.easeInOut(duration: 0.12), value: isHovered)
  }
}
