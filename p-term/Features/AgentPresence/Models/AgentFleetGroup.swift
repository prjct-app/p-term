import Foundation
import IdentifiedCollections
import PTermSettingsShared

/// One repository's worth of worktrees currently hosting a running agent.
/// Mirrors `ToolbarNotificationRepositoryGroup`'s repository → worktree
/// shape so the Fleet popover reads like a sibling of the notifications bell.
struct AgentFleetRepositoryGroup: Identifiable, Equatable {
  let id: Repository.ID
  let name: String
  let worktrees: [AgentFleetWorktreeGroup]

  var busyCount: Int {
    worktrees.reduce(0) { count, worktree in
      count + worktree.agents.filter { $0.activity == .busy }.count
    }
  }

  var awaitingInputCount: Int {
    worktrees.reduce(0) { count, worktree in
      count + worktree.agents.filter { $0.awaitingInput }.count
    }
  }
}

struct AgentFleetWorktreeGroup: Identifiable, Equatable {
  let id: Worktree.ID
  let name: String
  let branchName: String
  /// Awaiting-input instances sorted first (mirrors
  /// `AgentPresenceFeature.State.agents(across:)`'s ordering).
  let agents: [AgentPresenceFeature.AgentInstance]
}

extension AppFeature.State {
  /// Cross-project live agent fleet: every (surface, agent) with a presence
  /// record, grouped the same way the notifications bell groups worktrees.
  /// Pure computation over current state — no caching. Agent presence rows
  /// are few relative to sidebar size, so recomputing per render is cheap;
  /// unlike `toolbarNotificationGroupsCache` this isn't stored on state.
  func computeAgentFleetGroups() -> [AgentFleetRepositoryGroup] {
    guard !agentPresence.bySurface.isEmpty else { return [] }

    let surfaceToItemID = repositories.surfaceToItemID
    var instancesByWorktree: [Worktree.ID: [AgentPresenceFeature.AgentInstance]] = [:]
    for (surfaceID, agents) in agentPresence.bySurface {
      guard let worktreeID = surfaceToItemID[surfaceID] else { continue }
      for agent in agents {
        let key = AgentPresenceFeature.PresenceKey(agent: agent, surfaceID: surfaceID)
        let activity = agentPresence.records[key]?.activity ?? .idle
        instancesByWorktree[worktreeID, default: []].append(
          AgentPresenceFeature.AgentInstance(agent: agent, surfaceID: surfaceID, activity: activity)
        )
      }
    }
    guard !instancesByWorktree.isEmpty else { return [] }

    let repositoriesByID = Dictionary(uniqueKeysWithValues: repositories.repositories.map { ($0.id, $0) })
    var orderedIDs = repositories.orderedRepositoryIDs()
    let coveredIDs = Set(orderedIDs)
    for repository in repositories.repositories
    where repository.host != nil && !coveredIDs.contains(repository.id) {
      orderedIDs.append(repository.id)
    }

    var groups: [AgentFleetRepositoryGroup] = []
    for repositoryID in orderedIDs {
      guard let repository = repositoriesByID[repositoryID] else { continue }
      let worktreeGroups: [AgentFleetWorktreeGroup] =
        repositories.orderedWorktrees(in: repository).compactMap { worktree in
          guard let instances = instancesByWorktree[worktree.id], !instances.isEmpty else { return nil }
          let row = repositories.sidebarItems[id: worktree.id]
          let sorted = instances.sorted { lhs, rhs in
            if lhs.awaitingInput != rhs.awaitingInput { return lhs.awaitingInput }
            if lhs.agent.rawValue != rhs.agent.rawValue { return lhs.agent.rawValue < rhs.agent.rawValue }
            return lhs.surfaceID.uuidString < rhs.surfaceID.uuidString
          }
          return AgentFleetWorktreeGroup(
            id: worktree.id,
            name: row?.resolvedSidebarTitle ?? worktree.name,
            branchName: row?.branchName ?? "",
            agents: sorted
          )
        }
      if !worktreeGroups.isEmpty {
        groups.append(
          AgentFleetRepositoryGroup(id: repository.id, name: repository.name, worktrees: worktreeGroups)
        )
      }
    }
    return groups
  }
}
