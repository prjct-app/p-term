import ArgumentParser

@main
struct PTermCLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "p-term",
    abstract: "Control p/term from the command line.",
    subcommands: [
      OpenCommand.self,
      WorktreeCommand.self,
      TabCommand.self,
      SurfaceCommand.self,
      RepoCommand.self,
      SettingsCommand.self,
      SocketCommand.self,
    ],
    defaultSubcommand: OpenCommand.self
  )
}
