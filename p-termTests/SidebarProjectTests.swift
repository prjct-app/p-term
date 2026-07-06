import Dependencies
import Foundation
import OrderedCollections
import Testing

@testable import PTermSettingsShared
@testable import p_term

/// Locks the Phase 4 project-grouping invariants: single membership, contiguous
/// persisted order, referential pruning, and drag-to-group neighbor adoption.
@MainActor
struct SidebarProjectTests {
  private let repoA: Repository.ID = "/tmp/repo-a"
  private let repoB: Repository.ID = "/tmp/repo-b"
  private let repoC: Repository.ID = "/tmp/repo-c"
  private let projectX = ProjectID(rawValue: UUID(0))
  private let projectY = ProjectID(rawValue: UUID(1))

  private func stateWithSections(_ repos: [Repository.ID]) -> SidebarState {
    var state = SidebarState()
    for repo in repos {
      state.insert(worktree: Worktree.ID("wt-\(repo)"), in: repo, bucket: .unpinned)
    }
    return state
  }

  // MARK: - Membership

  @Test func addRepositoryEnforcesSingleMembership() {
    var state = stateWithSections([repoA, repoB])
    state.createProject(id: projectX, name: "X")
    state.createProject(id: projectY, name: "Y")
    state.addRepository(repoA, to: projectX)

    state.addRepository(repoA, to: projectY)

    #expect(state.projects[projectX]?.repositoryIDs == [])
    #expect(state.projects[projectY]?.repositoryIDs == [repoA])
    #expect(state.projectID(containing: repoA) == projectY)
  }

  @Test func addRepositoryToUnknownProjectLeavesRepoUngrouped() {
    var state = stateWithSections([repoA])
    state.addRepository(repoA, to: projectX)
    #expect(state.projectID(containing: repoA) == nil)
  }

  @Test func deleteProjectUngroupsMembersWithoutRemovingSections() {
    var state = stateWithSections([repoA, repoB])
    state.createProject(id: projectX, name: "X", repositoryIDs: [repoA, repoB])

    state.deleteProject(projectX)

    #expect(state.projectID(containing: repoA) == nil)
    #expect(state.sections[repoA] != nil)
    #expect(state.sections[repoB] != nil)
  }

  // MARK: - Contiguity reorder

  @Test func reorderGroupsMembersContiguousAtFirstMemberPosition() {
    // Persisted order A, B, C with A+C in a project → A, C, B (grouped at A's
    // slot, ungrouped B keeps relative position).
    var state = stateWithSections([repoA, repoB, repoC])
    state.createProject(id: projectX, name: "X", repositoryIDs: [repoA, repoC])

    state.reorderSectionsGroupingProjects()

    #expect(Array(state.sections.keys) == [repoA, repoC, repoB])
  }

  @Test func reorderIsStableWhenAlreadyGrouped() {
    var state = stateWithSections([repoA, repoC, repoB])
    state.createProject(id: projectX, name: "X", repositoryIDs: [repoA, repoC])

    state.reorderSectionsGroupingProjects()

    #expect(Array(state.sections.keys) == [repoA, repoC, repoB])
  }

  // MARK: - Prune

  @Test func pruneDropsDeadMembersAndReportsChange() {
    var state = stateWithSections([repoA])
    state.createProject(id: projectX, name: "X", repositoryIDs: [repoA, repoB])

    let changed = state.pruneProjects(liveRepositoryIDs: [repoA])
    let changedAgain = state.pruneProjects(liveRepositoryIDs: [repoA])

    #expect(changed)
    #expect(state.projects[projectX]?.repositoryIDs == [repoA])
    #expect(!changedAgain)
  }

  // MARK: - Drag-to-group neighbor adoption

  @Test func dropNextToProjectMemberJoinsViaPredecessor() {
    var state = stateWithSections([repoA, repoB, repoC])
    state.createProject(id: projectX, name: "X", repositoryIDs: [repoA])

    // C dragged to sit right after A (a member) → joins A's project.
    RepositoriesFeature.adoptProjectFromNeighbor(
      movedIDs: [repoC], ordered: [repoA, repoC, repoB], sidebar: &state)

    #expect(state.projectID(containing: repoC) == projectX)
  }

  @Test func dropAtTopJoinsViaSuccessor() {
    var state = stateWithSections([repoA, repoB, repoC])
    state.createProject(id: projectX, name: "X", repositoryIDs: [repoA])

    // C dragged to the very top, directly above member A → joins via successor.
    RepositoriesFeature.adoptProjectFromNeighbor(
      movedIDs: [repoC], ordered: [repoC, repoA, repoB], sidebar: &state)

    #expect(state.projectID(containing: repoC) == projectX)
  }

  @Test func dropAmongUngroupedLeavesProject() {
    var state = stateWithSections([repoA, repoB, repoC])
    state.createProject(id: projectX, name: "X", repositoryIDs: [repoA, repoC])

    // C dragged to the bottom, next to ungrouped B → leaves its project.
    RepositoriesFeature.adoptProjectFromNeighbor(
      movedIDs: [repoC], ordered: [repoA, repoB, repoC], sidebar: &state)

    #expect(state.projectID(containing: repoC) == nil)
  }

  @Test func multiRepoMoveDoesNotAdopt() {
    var state = stateWithSections([repoA, repoB, repoC])
    state.createProject(id: projectX, name: "X", repositoryIDs: [repoA])

    RepositoriesFeature.adoptProjectFromNeighbor(
      movedIDs: [repoB, repoC], ordered: [repoA, repoB, repoC], sidebar: &state)

    #expect(state.projectID(containing: repoB) == nil)
    #expect(state.projectID(containing: repoC) == nil)
  }
}
