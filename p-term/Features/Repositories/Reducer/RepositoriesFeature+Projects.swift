import ComposableArchitecture
import Foundation
import OrderedCollections

extension RepositoriesFeature {
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
