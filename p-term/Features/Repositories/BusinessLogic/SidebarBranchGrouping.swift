/// Pure first-seen-order grouping of per-entry branch keys, backing the
/// sidebar's per-workspace branch sub-headers. Lives in BusinessLogic (not the
/// view file) per the "view does zero computation" contract — and so the
/// grouping invariants (order preservation, exact partition, nil bucket) are
/// unit-testable without materializing view entry types.
enum SidebarBranchGrouping {
  static func grouped(branches: [String?]) -> [(branch: String?, indices: [Int])] {
    var order: [String?] = []
    var byBranch: [String: [Int]] = [:]
    var nilIndices: [Int] = []
    for (index, branch) in branches.enumerated() {
      if let branch {
        if byBranch[branch] == nil { order.append(branch) }
        byBranch[branch, default: []].append(index)
      } else {
        if nilIndices.isEmpty { order.append(nil) }
        nilIndices.append(index)
      }
    }
    return order.map { branch in
      (branch, branch.map { byBranch[$0] ?? [] } ?? nilIndices)
    }
  }
}
