import Foundation

/// Which signal the toolbar status island shows. `.auto` follows
/// `ToolbarStatusSignal.resolve(_:)`'s priority order (agent awaiting input >
/// agent working > running script > pull request > branch > time); the other
/// cases pin one signal, falling back to `.auto` when the pinned signal isn't
/// currently applicable (a pin never renders an empty capsule).
public nonisolated enum ToolbarStatusWidgetMode: String, Codable, CaseIterable, Sendable {
  case auto
  case agent
  case script
  case pullRequest
  case branch
  case time

  public var label: String {
    switch self {
    case .auto: "Auto"
    case .agent: "Agent"
    case .script: "Running Script"
    case .pullRequest: "Pull Request"
    case .branch: "Branch"
    case .time: "Time"
    }
  }
}
