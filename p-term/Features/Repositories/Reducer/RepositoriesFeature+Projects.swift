import ComposableArchitecture
import Foundation
import OrderedCollections

extension RepositoriesFeature {
  /// Phase 4 Stage 2 drag-to-group: after a single repo is dragged to a new
  /// position, adopt the project of the row it landed next to — its new
  /// predecessor (or, at the top, its successor). Dropped inside a project's
  /// block it joins that project; dropped among ungrouped rows it leaves any
  /// project it was in. No-op for multi-repo moves. `ordered` is the post-move
  /// repository order.
  static func adoptProjectFromNeighbor(
    movedIDs: [Repository.ID],
    ordered: [Repository.ID],
    sidebar: inout SidebarState
  ) {
    guard movedIDs.count == 1, let movedID = movedIDs.first,
      let index = ordered.firstIndex(of: movedID)
    else { return }
    let predecessor = index > 0 ? ordered[index - 1] : nil
    let successor = index < ordered.count - 1 ? ordered[index + 1] : nil
    let target =
      predecessor.flatMap { sidebar.projectID(containing: $0) }
      ?? successor.flatMap { sidebar.projectID(containing: $0) }
    guard sidebar.projectID(containing: movedID) != target else { return }
    if let target {
      sidebar.addRepository(movedID, to: target)
    } else {
      sidebar.removeRepositoryFromProjects(movedID)
    }
  }

  /// Phase 4 project-grouping actions. Split into its own reducer so the main
  /// `body` switch stays under the Swift type-checker's complexity limit.
  ///
  /// Every mutation folds through `state.$sidebar` and then
  /// `reorderSectionsGroupingProjects()` so a project's members stay contiguous
  /// in the persisted repo order — that's what keeps the rendered order 1:1 with
  /// `orderedRepositoryIDs()` and the drag/reorder machinery intact.
  static var projectsReducer: some Reducer<State, Action> {
    Reduce { state, action in
      @Dependency(\.uuid) var uuid
      switch action {
      case .createProject(let name, let repositoryIDs):
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = trimmed.isEmpty ? "New Project" : trimmed
        let projectID = ProjectID(rawValue: uuid())
        state.$sidebar.withLock { sidebar in
          sidebar.createProject(id: projectID, name: projectName)
          for repositoryID in repositoryIDs {
            sidebar.addRepository(repositoryID, to: projectID)
          }
          sidebar.reorderSectionsGroupingProjects()
        }
        syncSidebar(&state)
        return .none

      case .renameProject(let projectID, let title):
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        state.$sidebar.withLock { $0.renameProject(projectID, name: trimmed) }
        syncSidebar(&state)
        return .none

      case .setProjectColor(let projectID, let color):
        state.$sidebar.withLock { $0.setProjectColor(projectID, color: color) }
        syncSidebar(&state)
        return .none

      case .toggleProjectCollapsed(let projectID):
        state.$sidebar.withLock { sidebar in
          let collapsed = sidebar.projects[projectID]?.collapsed ?? false
          sidebar.setProjectCollapsed(projectID, collapsed: !collapsed)
        }
        syncSidebar(&state)
        return .none

      case .addRepositoryToProject(let repositoryID, let projectID):
        state.$sidebar.withLock { sidebar in
          sidebar.addRepository(repositoryID, to: projectID)
          sidebar.reorderSectionsGroupingProjects()
        }
        syncSidebar(&state)
        return .none

      case .removeRepositoryFromProject(let repositoryID):
        state.$sidebar.withLock { sidebar in
          sidebar.removeRepositoryFromProjects(repositoryID)
          sidebar.reorderSectionsGroupingProjects()
        }
        syncSidebar(&state)
        return .none

      case .deleteProject(let projectID):
        state.$sidebar.withLock { sidebar in
          sidebar.deleteProject(projectID)
          sidebar.reorderSectionsGroupingProjects()
        }
        syncSidebar(&state)
        return .none

      default:
        return .none
      }
    }
  }
}
