import PTermSettingsShared
import SwiftUI

struct CLIReferenceView: View {
  var body: some View {
    Form {
      // swiftlint:disable line_length
      Section {
        Text(
          "The \(code("p-term")) command is available in all prjct terminal sessions. Run \(code("p-term --help")) for built-in usage information."
        )
        .foregroundStyle(.secondary)
        Text(
          "Inside a prjct terminal, flags default to the current session's IDs. Outside, pass explicit IDs from \(code("p-term worktree list")) or \(code("p-term repo list"))."
        )
        .foregroundStyle(.secondary)
        Text(
          "Commands that create resources (\(code("tab new")), \(code("surface split"))) print the new UUID to stdout. Capture it to target the resource afterward."
        )
        .foregroundStyle(.secondary)
        // swiftlint:enable line_length
      } header: {
        Text("CLI Reference").font(AppTypography.title.bold())
        Text("Control prjct from the terminal.")
      }

      CLISection(title: "App", rows: Self.appRows)
      CLISection(title: "Worktree", rows: Self.worktreeRows)
      CLISection(title: "Tab", rows: Self.tabRows)
      CLISection(title: "Surface", rows: Self.surfaceRows)
      CLISection(title: "Repository", rows: Self.repoRows)
      CLISection(title: "Settings", rows: Self.settingsRows)
      CLISection(title: "Socket", rows: Self.socketRows)

      Section("Flags") {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
          ForEach(Self.flagRows) { row in
            GridRow {
              Text(row.command)
                .font(.body.monospaced())
                .gridColumnAlignment(.leading)
              Text(row.description)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            }
          }
        }
      }
    }
    .textSelection(.enabled)
    .formStyle(.grouped)
    .frame(minWidth: 300)
    .navigationTitle("")
  }

  // MARK: - Row data.

  private static let appRows: [CLIEntry] = [
    .init(command: "p-term", description: "Bring prjct to front."),
    .init(command: "p-term open", description: "Same as above."),
  ]

  private static let worktreeRows: [CLIEntry] = [
    .init(command: "p-term worktree list [-f]", description: "List worktree IDs. -f for focused only."),
    .init(command: "p-term worktree focus [-w <id>]", description: "Focus a worktree."),
    .init(
      command: "p-term worktree run [-w <id>] [-c <uuid>]",
      description: "Run a script. Defaults to the primary run-kind script; -c targets a specific one."
    ),
    .init(
      command: "p-term worktree stop [-w <id>] [-c <uuid>]",
      description: "Stop a script. Defaults to all run-kind scripts; -c targets a specific one."
    ),
    .init(
      command: "p-term worktree script list [-w <id>]",
      description: "List configured scripts. Underlined rows are currently running."
    ),
    .init(command: "p-term worktree archive [-w <id>]", description: "Archive the worktree."),
    .init(command: "p-term worktree unarchive [-w <id>]", description: "Unarchive the worktree."),
    .init(command: "p-term worktree delete [-w <id>]", description: "Delete the worktree."),
    .init(command: "p-term worktree pin [-w <id>]", description: "Pin the worktree."),
    .init(command: "p-term worktree unpin [-w <id>]", description: "Unpin the worktree."),
  ]

  private static let tabRows: [CLIEntry] = [
    .init(command: "p-term tab list [-w <id>] [-f]", description: "List tab UUIDs. -f for focused only."),
    .init(command: "p-term tab focus [-w <id>] [-t <id>]", description: "Focus a tab."),
    .init(
      command: "p-term tab new [-w <id>] [-i <cmd>] [-n <uuid>]",
      description: "Create a new tab. Prints UUID to stdout."
    ),
    .init(command: "p-term tab close [-w <id>] [-t <id>]", description: "Close a tab."),
  ]

  private static let surfaceRows: [CLIEntry] = [
    .init(
      command: "p-term surface list [-w <id>] [-t <id>] [-f]",
      description: "List surface UUIDs. -f for focused only."
    ),
    .init(
      command: "p-term surface focus [-w <id>] [-t <id>] [-s <id>] [-i <cmd>]",
      description: "Focus a surface."
    ),
    .init(
      command: "p-term surface split [-w <id>] [-t <id>] [-s <id>] [-d h|v] [-i <cmd>] [-n <uuid>]",
      description: "Split a surface. Prints UUID to stdout."
    ),
    .init(
      command: "p-term surface close [-w <id>] [-t <id>] [-s <id>]",
      description: "Close a surface."
    ),
  ]

  private static let repoRows: [CLIEntry] = [
    .init(command: "p-term repo list", description: "List repository IDs."),
    .init(command: "p-term repo open <path>", description: "Open a repository."),
    .init(
      command:
        "p-term repo worktree-new [-r <id>] [--branch <name>] [--base <ref>] [--fetch] "
        + "[--name <folder>] [--location <dir>]",
      description: "Create a worktree in a repository."
    ),
  ]

  private static let settingsRows: [CLIEntry] = [
    .init(command: "p-term settings", description: "Open settings."),
    .init(command: "p-term settings <section>", description: "Open a specific section."),
    .init(command: "p-term settings repo [-r <id>]", description: "Open repository settings."),
  ]

  private static let socketRows: [CLIEntry] = [
    .init(command: "p-term socket", description: "List active socket paths.")
  ]

  private static let flagRows: [CLIEntry] = [
    .init(command: "-w, --worktree", description: "Worktree ID. Defaults to $P_TERM_WORKTREE_ID."),
    .init(command: "-t, --tab", description: "Tab UUID. Defaults to $P_TERM_TAB_ID."),
    .init(command: "-s, --surface", description: "Surface UUID. Defaults to $P_TERM_SURFACE_ID."),
    .init(command: "-c, --script", description: "Script UUID (for `worktree run`/`stop`)."),
    .init(command: "-r, --repo", description: "Repository ID. Defaults to $P_TERM_REPO_ID."),
    .init(command: "-i, --input", description: "Command to run in the terminal."),
    .init(command: "-d, --direction", description: "Split direction: horizontal (h) or vertical (v)."),
    .init(command: "-n, --id", description: "UUID for a new tab or surface."),
    .init(command: "-f, --focused", description: "Print only the focused item in list commands."),
  ]
}

// MARK: - Components.

private struct CLIEntry: Identifiable {
  let id = UUID()
  let command: String
  let description: String
}

private struct CLISection: View {
  let title: String
  let rows: [CLIEntry]

  var body: some View {
    Section(title) {
      Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
        ForEach(rows) { row in
          GridRow {
            Text(row.command)
              .font(.body.monospaced())
              .gridColumnAlignment(.leading)
            Text(row.description)
              .foregroundStyle(.secondary)
              .gridColumnAlignment(.leading)
          }
        }
      }
    }
  }
}

/// Inline code fragment styled as monospaced primary foreground.
private func code(_ value: String) -> Text {
  Text(value).monospaced().foregroundStyle(.primary)
}
