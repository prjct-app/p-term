import ArgumentParser

/// `task` frames worktrees as the unit of work ("tasks") and surfaces their live agent status —
/// the CLI view of the parallel-agent model p/term is built around. A task IS a worktree, so
/// `focus` reuses the worktree machinery; `list` is the value add: one glance at every task and
/// whether its agent is working, waiting, or idle.
struct TaskCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "task",
    abstract: "List and focus tasks (worktrees) with their live agent status.",
    subcommands: [
      List.self,
      Focus.self,
    ],
    defaultSubcommand: List.self
  )
}

extension TaskCommand {
  struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List tasks as columns: <status>\t<repo>/<branch>\t<id>. The focused task is underlined."
    )

    @Flag(name: [.short, .long], help: "Only tasks whose agent is awaiting input.")
    var waiting = false

    @Flag(name: [.short, .long], help: "Only the focused task.")
    var focused = false

    func run() throws {
      let items = try QueryDispatcher.query(resource: "worktrees")
      for item in items {
        let isFocused = !(item["focused"] ?? "").isEmpty
        let status = item["status"] ?? "idle"
        guard !focused || isFocused else { continue }
        guard !waiting || status == "waiting" else { continue }
        print(formatTaskListLine(item, focused: isFocused))
      }
    }
  }

  struct Focus: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Focus a task (worktree).")

    @Option(name: [.short, .long], help: "Worktree ID. Defaults to $P_TERM_WORKTREE_ID.")
    var worktree: String?

    func run() throws {
      let id = try resolveWorktreeID(worktree)
      try Dispatcher.dispatch(deeplinkURL: DeeplinkURLBuilder.worktreeSelect(worktreeID: id))
    }
  }
}
