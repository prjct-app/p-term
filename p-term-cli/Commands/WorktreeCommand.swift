import ArgumentParser
import Foundation

struct WorktreeCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "worktree",
    // Product language is "workspace"; keep `worktree` as the primary wire
    // name for scripts/env ($P_TERM_WORKTREE_ID) and accept `workspace` as alias.
    abstract: "Manage workspaces (terminal workspaces / git worktrees).",
    subcommands: [
      List.self,
      Focus.self,
      Run.self,
      Stop.self,
      WorktreeScriptCommand.self,
      Archive.self,
      Unarchive.self,
      Delete.self,
      Pin.self,
      Unpin.self,
    ],
    defaultSubcommand: Focus.self,
    aliases: ["workspace"]
  )
}

// MARK: - Subcommands.

extension WorktreeCommand {
  struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List workspaces.")

    @Flag(name: [.short, .long], help: "Print only the focused workspace.")
    var focused = false

    func run() throws {
      let items = try QueryDispatcher.query(resource: "worktrees")
      for item in items {
        let isFocused = !(item["focused"] ?? "").isEmpty
        guard !focused || isFocused else { continue }
        print(formatListLine(item["id"] ?? "", focused: isFocused))
      }
    }
  }

  struct Focus: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Focus a workspace.")

    @Option(name: [.short, .long], help: "Workspace ID. Defaults to $P_TERM_WORKTREE_ID.")
    var worktree: String?

    func run() throws {
      let id = try resolveWorktreeID(worktree)
      try Dispatcher.dispatch(deeplinkURL: DeeplinkURLBuilder.worktreeSelect(worktreeID: id))
    }
  }

  struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Run a script. Defaults to the primary run-kind script when --script is omitted."
    )

    @Option(name: [.short, .long], help: "Workspace ID. Defaults to $P_TERM_WORKTREE_ID.")
    var worktree: String?

    @Option(name: [.customShort("c"), .long], help: "Script UUID (see `workspace script list`).")
    var script: String?

    func run() throws {
      let id = try resolveWorktreeID(worktree)
      guard let script else {
        try Dispatcher.dispatch(deeplinkURL: DeeplinkURLBuilder.worktreeAction("run", worktreeID: id))
        return
      }
      let scriptID = try validatedScriptID(script)
      try Dispatcher.dispatch(
        deeplinkURL: DeeplinkURLBuilder.scriptRun(worktreeID: id, scriptID: scriptID)
      )
    }
  }

  struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Stop a running script. Defaults to all run-kind scripts when --script is omitted."
    )

    @Option(name: [.short, .long], help: "Workspace ID. Defaults to $P_TERM_WORKTREE_ID.")
    var worktree: String?

    @Option(name: [.customShort("c"), .long], help: "Script UUID (see `workspace script list`).")
    var script: String?

    func run() throws {
      let id = try resolveWorktreeID(worktree)
      guard let script else {
        try Dispatcher.dispatch(deeplinkURL: DeeplinkURLBuilder.worktreeAction("stop", worktreeID: id))
        return
      }
      let scriptID = try validatedScriptID(script)
      try Dispatcher.dispatch(
        deeplinkURL: DeeplinkURLBuilder.scriptStop(worktreeID: id, scriptID: scriptID)
      )
    }
  }

  struct Archive: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Archive the workspace.")

    @Option(name: [.short, .long], help: "Workspace ID. Defaults to $P_TERM_WORKTREE_ID.")
    var worktree: String?

    func run() throws {
      let id = try resolveWorktreeID(worktree)
      try Dispatcher.dispatch(deeplinkURL: DeeplinkURLBuilder.worktreeAction("archive", worktreeID: id))
    }
  }

  struct Unarchive: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Unarchive the workspace.")

    @Option(name: [.short, .long], help: "Workspace ID. Defaults to $P_TERM_WORKTREE_ID.")
    var worktree: String?

    func run() throws {
      let id = try resolveWorktreeID(worktree)
      try Dispatcher.dispatch(deeplinkURL: DeeplinkURLBuilder.worktreeAction("unarchive", worktreeID: id))
    }
  }

  struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete the workspace.")

    @Option(name: [.short, .long], help: "Workspace ID. Defaults to $P_TERM_WORKTREE_ID.")
    var worktree: String?

    func run() throws {
      let id = try resolveWorktreeID(worktree)
      try Dispatcher.dispatch(deeplinkURL: DeeplinkURLBuilder.worktreeAction("delete", worktreeID: id))
    }
  }

  struct Pin: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Pin the workspace.")

    @Option(name: [.short, .long], help: "Workspace ID. Defaults to $P_TERM_WORKTREE_ID.")
    var worktree: String?

    func run() throws {
      let id = try resolveWorktreeID(worktree)
      try Dispatcher.dispatch(deeplinkURL: DeeplinkURLBuilder.worktreeAction("pin", worktreeID: id))
    }
  }

  struct Unpin: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Unpin the workspace.")

    @Option(name: [.short, .long], help: "Workspace ID. Defaults to $P_TERM_WORKTREE_ID.")
    var worktree: String?

    func run() throws {
      let id = try resolveWorktreeID(worktree)
      try Dispatcher.dispatch(deeplinkURL: DeeplinkURLBuilder.worktreeAction("unpin", worktreeID: id))
    }
  }
}
