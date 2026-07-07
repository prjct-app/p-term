import Foundation

/// A "paper window manager" (Niri-style) view of one tab's panes: columns
/// laid out left-to-right, each a top-to-bottom stack. This is purely a
/// different SPATIAL PRESENTATION of the same panes the tiling `SplitTree`
/// holds — pane membership is identical, only arrangement/geometry differs.
/// Each column has its own independently user-resizable width and can be
/// drag-reordered; neither maps back onto the tree's split ratios/structure.
///
/// Persisted via `TerminalLayoutSnapshot.TabSnapshot.layoutMode`/`paperColumns`.
struct PaperLayout: Equatable {
  struct Column: Equatable, Identifiable {
    let id: UUID
    var paneIDs: [UUID]
    /// User-resizable; independent per column (dragging one column's handle
    /// never touches its neighbors' widths).
    var width: CGFloat

    init(id: UUID, paneIDs: [UUID], width: CGFloat = PaperLayout.defaultColumnWidth) {
      self.id = id
      self.paneIDs = paneIDs
      self.width = width
    }
  }

  var columns: [Column]

  static let defaultColumnWidth: CGFloat = 420
  static let minColumnWidth: CGFloat = 240
  static let maxColumnWidth: CGFloat = 960

  init(columns: [Column] = []) {
    self.columns = columns
  }

  var isEmpty: Bool { columns.isEmpty }

  var allPaneIDs: [UUID] {
    columns.flatMap(\.paneIDs)
  }

  func columnIndex(containing paneID: UUID) -> Int? {
    columns.firstIndex { $0.paneIDs.contains(paneID) }
  }

  /// Removes a pane (e.g. on close); drops the column entirely if it was
  /// that column's only pane.
  func removing(paneID: UUID) -> PaperLayout {
    var next = self
    next.columns = next.columns.compactMap { column in
      var column = column
      column.paneIDs.removeAll { $0 == paneID }
      return column.paneIDs.isEmpty ? nil : column
    }
    return next
  }

  /// Appends a new pane as its own trailing column (the common case: a
  /// fresh split in paper mode reads as "one more column to scroll to").
  /// Inherits the previous last column's width rather than resetting to
  /// `defaultColumnWidth` — a freshly split pane should open the same size
  /// as its neighbor, not snap back to some unrelated default.
  func addingColumn(paneID: UUID) -> PaperLayout {
    var next = self
    let width = columns.last?.width ?? Self.defaultColumnWidth
    next.columns.append(Column(id: UUID(), paneIDs: [paneID], width: width))
    return next
  }

  /// Clamped to `minColumnWidth...maxColumnWidth` so a drag can't shrink a
  /// column to nothing or blow it up past anything reasonable.
  func settingWidth(_ width: CGFloat, forColumn columnID: UUID) -> PaperLayout {
    var next = self
    guard let index = next.columns.firstIndex(where: { $0.id == columnID }) else { return self }
    next.columns[index].width = max(Self.minColumnWidth, min(Self.maxColumnWidth, width))
    return next
  }

  /// Reorders a column to sit immediately before `destinationColumnID` —
  /// the drag-to-reorder gesture in `PaperLayoutView` calls this on drop.
  /// `nil` destination (dropped past the last column, or onto itself) moves
  /// it to the end. No-op if `columnID` isn't found.
  func movingColumn(_ columnID: UUID, before destinationColumnID: UUID?) -> PaperLayout {
    var next = self
    guard let sourceIndex = next.columns.firstIndex(where: { $0.id == columnID }) else { return self }
    let column = next.columns.remove(at: sourceIndex)
    guard let destinationColumnID, destinationColumnID != columnID,
      // Recompute the destination AFTER removal — removing the source
      // shifts every index after it, including the destination's if later.
      let destinationIndex = next.columns.firstIndex(where: { $0.id == destinationColumnID })
    else {
      next.columns.append(column)
      return next
    }
    next.columns.insert(column, at: destinationIndex)
    return next
  }
}

extension PaperLayout {
  /// Builds a paper layout from the tiling tree: each leaf becomes its own
  /// column; a `.vertical` split's two sides stack into ONE column (top
  /// then bottom) as long as neither side is itself already multi-column
  /// (i.e. no nested horizontal split within it) — that case falls back to
  /// keeping the sides as separate column groups rather than merging
  /// incompatible shapes.
  static func from(tree: SplitTree<PaneLeafView>) -> PaperLayout {
    guard let root = tree.root else { return PaperLayout() }
    let stacks = collectColumnStacks(root)
    return PaperLayout(columns: stacks.map { Column(id: UUID(), paneIDs: $0) })
  }

  private static func collectColumnStacks(_ node: SplitTree<PaneLeafView>.Node) -> [[UUID]] {
    switch node {
    case .leaf(let view):
      return [[view.id]]
    case .split(let split):
      switch split.direction {
      case .vertical:
        let left = collectColumnStacks(split.left)
        let right = collectColumnStacks(split.right)
        if left.count == 1, right.count == 1 {
          return [left[0] + right[0]]
        }
        return left + right
      case .horizontal:
        return collectColumnStacks(split.left) + collectColumnStacks(split.right)
      }
    }
  }

  /// Rebuilds a tiling `SplitTree` from this paper layout, anchoring on
  /// EXISTING `PaneLeafView` instances (via `resolve`) — never constructs
  /// new leaves, so identity-sensitive tree operations elsewhere
  /// (`inserting`'s `===` anchor lookup) keep working after a toggle.
  ///
  /// Builds the horizontal column skeleton FIRST (one representative pane
  /// per column, left to right), THEN stacks each column's remaining panes
  /// vertically within their own already-placed slot. This ordering is
  /// load-bearing: stacking a column before every column's skeleton slot
  /// exists would nest a later column's insertion inside an earlier
  /// column's now-multi-pane subtree instead of beside it, corrupting the
  /// geometry (a later column would only span part of the height instead
  /// of the full column).
  func makeSplitTree(resolve: (UUID) -> PaneLeafView?) throws -> SplitTree<PaneLeafView>? {
    let resolvedColumns = columns.map { $0.paneIDs.compactMap(resolve) }.filter { !$0.isEmpty }
    guard let firstColumn = resolvedColumns.first, let firstPane = firstColumn.first else {
      return nil
    }
    var tree = SplitTree(view: firstPane)
    var columnHeads: [PaneLeafView] = [firstPane]
    for column in resolvedColumns.dropFirst() {
      guard let head = column.first else { continue }
      tree = try tree.inserting(view: head, at: columnHeads[columnHeads.count - 1], direction: .right)
      columnHeads.append(head)
    }
    for (column, head) in zip(resolvedColumns, columnHeads) {
      var previous = head
      for pane in column.dropFirst() {
        tree = try tree.inserting(view: pane, at: previous, direction: .down)
        previous = pane
      }
    }
    return tree.equalized()
  }
}
