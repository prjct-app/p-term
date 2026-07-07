/// Identifiers for the app's SwiftUI `Window` scenes.
enum WindowID {
  static let main = "main"
  static let settings = "settings"
  static let activity = "activity"
  static let cloud = "cloud"
  static let memory = "memory"
  static let deeplinkReference = "deeplink-reference"
  static let cliReference = "cli-reference"
  #if DEBUG
    /// C0 spike scene (see the agentic-DX roadmap plan) — never shipped in Release.
    static let paperLayoutSpike = "paper-layout-spike"
  #endif
}
