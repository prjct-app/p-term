import Foundation
import PTermSettingsShared

/// Stable identity of a user-created **Project** — the top grouping level that
/// gathers several repositories/folders under one name (e.g. "Proyecto X" =
/// a frontend repo + a backend repo). Branded over `UUID` so a project id can't
/// be confused with a `Repository.ID` (which is path-derived).
nonisolated struct ProjectID: Hashable, Codable, Sendable {
  let rawValue: UUID

  init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

/// A user-created project grouping several repositories in the sidebar. Lives in
/// `SidebarState` (persisted to `sidebar.json`) keyed by `ProjectID`; membership
/// is by `Repository.ID` so the `Repository` domain model stays free of any
/// parent/group concept (its identity is purely its location).
///
/// In Phase 4 Stage 1 a project is a purely PRESENTATIONAL grouping — it renders
/// a collapsible header above its member repositories but does not yet own the
/// top-level repo ordering (that stays with `SidebarState.sections`). Later
/// stages make membership/order the ordering authority.
nonisolated struct SidebarProject: Equatable, Sendable, Codable, Identifiable {
  let id: ProjectID
  /// User-facing name. Never empty after a trimmed rename (callers guard).
  var name: String
  /// Optional tint for the project header.
  var color: RepositoryColor?
  /// Member repositories, in the order they appear under the header.
  var repositoryIDs: [Repository.ID]
  /// Whether the header is collapsed (member repos hidden).
  var collapsed: Bool

  init(
    id: ProjectID = ProjectID(),
    name: String,
    color: RepositoryColor? = nil,
    repositoryIDs: [Repository.ID] = [],
    collapsed: Bool = false
  ) {
    self.id = id
    self.name = name
    self.color = color
    self.repositoryIDs = repositoryIDs
    self.collapsed = collapsed
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, color, repositoryIDs, collapsed
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(ProjectID.self, forKey: .id)
    self.name = try container.decode(String.self, forKey: .name)
    // `try?` so a color value an older/newer build doesn't understand drops the
    // field, not the whole project.
    self.color = (try? container.decodeIfPresent(RepositoryColor.self, forKey: .color)) ?? nil
    self.repositoryIDs = try container.decodeIfPresent([Repository.ID].self, forKey: .repositoryIDs) ?? []
    self.collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encodeIfPresent(color, forKey: .color)
    try container.encode(repositoryIDs, forKey: .repositoryIDs)
    try container.encode(collapsed, forKey: .collapsed)
  }
}
