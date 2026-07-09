import Foundation
import Observation
import PTermSettingsShared

@MainActor
@Observable
final class TerminalTabManager {
  var tabs: [TerminalTabItem] = [] {
    // Drops `editingTabID` when the edited tab disappears across any close path.
    // Rebuilds the O(1) id→index map on every mutation so title/progress storms
    // do not pay linear scans per report.
    didSet {
      rebuildIndex()
      guard let id = editingTabID, indexByID[id] == nil else { return }
      editingTabID = nil
    }
  }
  var selectedTabId: TerminalTabID?
  private(set) var editingTabID: TerminalTabID?

  /// Reverse index maintained in `tabs.didSet`. Prefer `index(of:)` over
  /// `tabs.firstIndex(where:)` on every high-frequency mutator.
  private var indexByID: [TerminalTabID: Int] = [:]

  private static let logger = PTermLogger("TabManager")

  private func rebuildIndex() {
    var map: [TerminalTabID: Int] = [:]
    map.reserveCapacity(tabs.count)
    for (offset, tab) in tabs.enumerated() {
      map[tab.id] = offset
    }
    indexByID = map
  }

  private func index(of id: TerminalTabID) -> Int? {
    indexByID[id]
  }

  func createTab(
    title: String,
    icon: String?,
    isTitleLocked: Bool = false,
    tintColor: RepositoryColor? = nil,
    isBlockingScript: Bool = false,
    id: UUID? = nil
  ) -> TerminalTabID {
    let tabID: TerminalTabID
    if let id {
      let candidate = TerminalTabID(rawValue: id)
      if indexByID[candidate] != nil {
        Self.logger.warning("Duplicate tab ID \(id), generating a new one.")
        tabID = TerminalTabID()
      } else {
        tabID = candidate
      }
    } else {
      tabID = TerminalTabID()
    }
    let tab = TerminalTabItem(
      id: tabID,
      title: title,
      icon: icon,
      isTitleLocked: isTitleLocked,
      tintColor: tintColor,
      isBlockingScript: isBlockingScript
    )
    if let selectedTabId, let selectedIndex = index(of: selectedTabId) {
      tabs.insert(tab, at: selectedIndex + 1)
    } else {
      tabs.append(tab)
    }
    selectedTabId = tab.id
    return tab.id
  }

  func selectTab(_ id: TerminalTabID) {
    guard indexByID[id] != nil else { return }
    selectedTabId = id
  }

  func updateTitle(_ id: TerminalTabID, title: String) {
    guard let index = index(of: id) else { return }
    guard !tabs[index].isTitleLocked else { return }
    // TUIs rewrite their title constantly; skip no-op writes so an unchanged
    // title doesn't re-render the tab bar on every report.
    guard tabs[index].title != title else { return }
    tabs[index].title = title
  }

  func setCustomTitle(_ id: TerminalTabID, title: String) {
    guard let index = index(of: id) else { return }
    guard !tabs[index].isTitleLocked else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    tabs[index].customTitle = trimmed.isEmpty ? nil : trimmed
  }

  func setTintColor(_ id: TerminalTabID, color: RepositoryColor?) {
    guard let index = index(of: id) else { return }
    guard tabs[index].tintColor != color else { return }
    tabs[index].tintColor = color
  }

  func isBlockingScript(_ id: TerminalTabID) -> Bool {
    guard let index = index(of: id) else { return false }
    return tabs[index].isBlockingScript
  }

  /// Mark a blocking-script tab as completed. Title / icon / lock survive so
  /// the row reads as "this WAS an Archive Script run"; tint + dirty clear and
  /// the completed flag flips so views can show the freeze indicator.
  func markBlockingScriptCompleted(_ id: TerminalTabID) {
    guard let index = index(of: id) else { return }
    tabs[index].tintColor = nil
    tabs[index].isDirty = false
    tabs[index].isBlockingScriptCompleted = true
  }

  func updateDirty(_ id: TerminalTabID, isDirty: Bool) {
    guard let index = index(of: id),
      tabs[index].isDirty != isDirty
    else { return }
    tabs[index].isDirty = isDirty
  }

  func reorderTabs(_ orderedIds: [TerminalTabID]) {
    let existingIds = Set(tabs.map(\.id))
    let incomingIds = Set(orderedIds)
    guard existingIds == incomingIds else { return }
    let map = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
    tabs = orderedIds.compactMap { map[$0] }
  }

  func closeTab(_ id: TerminalTabID) {
    guard let index = index(of: id) else { return }
    tabs.remove(at: index)
    guard selectedTabId == id else { return }
    if index > 0 {
      selectedTabId = tabs[index - 1].id
    } else if !tabs.isEmpty {
      selectedTabId = tabs[0].id
    } else {
      selectedTabId = nil
    }
  }

  func closeOthers(keeping id: TerminalTabID) {
    tabs = tabs.filter { $0.id == id }
    selectedTabId = tabs.first?.id
  }

  func closeToRight(of id: TerminalTabID) {
    guard let index = index(of: id) else { return }
    tabs = Array(tabs.prefix(index + 1))
    if let selectedTabId, indexByID[selectedTabId] == nil {
      // `tabs` assignment already rebuilt the index; re-check membership.
      self.selectedTabId = tabs.last?.id
    }
  }

  func beginTabRename(_ id: TerminalTabID) {
    guard let index = index(of: id), !tabs[index].isTitleLocked else { return }
    editingTabID = id
  }

  func endTabRename() {
    editingTabID = nil
  }

  func closeAll() {
    tabs.removeAll()
    selectedTabId = nil
  }
}
