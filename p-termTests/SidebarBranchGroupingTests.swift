import Testing

@testable import p_term

/// Locks the branch-grouping invariants behind the sidebar's per-workspace
/// branch sub-headers: first-seen order, exact partition, nil bucket placement.
@MainActor
struct SidebarBranchGroupingTests {
  @Test func preservesFirstSeenOrderAndPartitionsExactly() {
    let groups = SidebarBranchGrouping.grouped(
      branches: ["main", "feat/x", "main", nil, "feat/x"])
    #expect(groups.map(\.branch) == ["main", "feat/x", nil])
    #expect(groups.map(\.indices) == [[0, 2], [1, 4], [3]])
  }

  @Test func nilBucketKeepsFirstSeenPosition() {
    let groups = SidebarBranchGrouping.grouped(branches: [nil, "main", nil])
    #expect(groups.map(\.branch) == [nil, "main"])
    #expect(groups.map(\.indices) == [[0, 2], [1]])
  }

  @Test func singleBranchYieldsOneGroup() {
    let groups = SidebarBranchGrouping.grouped(branches: ["main", "main"])
    #expect(groups.count == 1)
    #expect(groups[0].branch == "main")
    #expect(groups[0].indices == [0, 1])
  }

  @Test func emptyInputYieldsNoGroups() {
    #expect(SidebarBranchGrouping.grouped(branches: []).isEmpty)
  }
}
