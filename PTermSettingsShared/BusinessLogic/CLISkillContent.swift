/// Content for the p/term CLI skill installed into coding agent configs.
nonisolated enum CLISkillContent {
  static let skillName = "p-term-cli"

  static let description =
    "Control p/term from the terminal."
    + " Use when running p/term CLI commands, managing worktrees, tabs, and surfaces programmatically,"
    + " or when inside a p/term terminal session."

  // MARK: - Claude Code.

  static let claudeSkill = """
    ---
    name: \(skillName)
    description: \(description)
    ---

    # p/term CLI

    Control p/term from the terminal. The `p-term` command is available in all p/term terminal sessions.

    ## CRITICAL: ID Tracking

    **NEVER call `p-term tab new` or `p-term surface split` without capturing
    the output.** These commands print the new resource UUID to stdout. You MUST
    capture it into a variable — without it you cannot target the resource afterward.

    **NEVER omit `-t` and `-s` flags when targeting a resource you created.**
    The environment variables `$P_TERM_TAB_ID` and `$P_TERM_SURFACE_ID` refer
    to the shell session you are running in, NOT to any tab or surface you created.
    If you omit `-t`/`-s`, the command targets your own shell — not the new resource.

    For new tabs, the initial surface ID equals the tab ID.

    ### Correct pattern — ALWAYS follow this:

    **Run all related commands in a SINGLE Bash call** so captured variables
    are available to subsequent commands. If you split across tool calls,
    variables like `$TAB_ID` will be lost.

    ```sh
    # 1. ALWAYS capture the UUID from tab new / surface split.
    TAB_ID=$(p-term tab new -i "npm start")

    # 2. ALWAYS pass -t and -s explicitly when targeting created resources.
    #    For new tabs: surface ID = tab ID.
    SPLIT_ID=$(p-term surface split -t "$TAB_ID" -s "$TAB_ID" -d v -i "npm test")

    # 3. ALWAYS use captured IDs for subsequent operations.
    p-term surface focus -t "$TAB_ID" -s "$SPLIT_ID" -i "echo hello"
    p-term surface close -t "$TAB_ID" -s "$SPLIT_ID"
    p-term tab close -t "$TAB_ID"
    ```

    ### WRONG — never do this:

    ```sh
    # BAD: not capturing the UUID — you lose the reference.
    p-term tab new -i "npm start"

    # BAD: missing -t/-s — this targets your own shell, not the new tab.
    p-term surface split -d v -i "npm test"

    # BAD: splitting commands across separate Bash calls — variables are lost.
    # Call 1: TAB_ID=$(p-term tab new)
    # Call 2: p-term surface split -t "$TAB_ID" ...  ← $TAB_ID is empty!
    ```

    ## Environment

    Inside p/term terminals, these environment variables are set automatically:

    | Variable | Description |
    |----------|-------------|
    | `P_TERM_WORKTREE_ID` | Current worktree (percent-encoded path). |
    | `P_TERM_TAB_ID` | Current tab UUID (your shell's tab, not created ones). |
    | `P_TERM_SURFACE_ID` | Current surface UUID (your shell's surface, not created ones). |
    | `P_TERM_REPO_ID` | Current repository (percent-encoded path). |
    | `P_TERM_SOCKET_PATH` | Socket for app communication. |

    `-w`, `-t`, `-s`, `-r` default to these when omitted. This is only useful for
    targeting **your own** session. For anything you create, pass explicit IDs.

    ## Commands

    ### App

    ```
    p-term                          # Bring p/term to front.
    p-term open                     # Same as above.
    ```

    ### Worktree

    ```
    p-term worktree list [-f]                          # List worktree IDs (-f = focused only).
    p-term worktree focus [-w <id>]                   # Focus worktree.
    p-term worktree run [-w <id>] [-c <uuid>]         # Run script (default: primary run-kind; -c for a specific UUID).
    p-term worktree stop [-w <id>] [-c <uuid>]        # Stop script (default: all run-kind; -c for a specific UUID).
    p-term worktree script list [-w <id>]             # List configured scripts (id / kind / name). Running rows are underlined.
    p-term worktree archive [-w <id>]                 # Archive worktree.
    p-term worktree unarchive [-w <id>]               # Unarchive worktree.
    p-term worktree delete [-w <id>]                  # Delete worktree.
    p-term worktree pin [-w <id>]                     # Pin worktree.
    p-term worktree unpin [-w <id>]                   # Unpin worktree.
    ```

    ### Tab

    ```
    p-term tab list [-w <id>] [-f]                              # List tab UUIDs in worktree (-f = focused only).
    p-term tab focus [-w <id>] [-t <id>]                      # Focus tab.
    p-term tab new [-w <id>] [-i <cmd>] [-n <uuid>]           # Create new tab (prints UUID to stdout).
    p-term tab close [-w <id>] [-t <id>]                      # Close tab.
    ```

    ### Surface

    ```
    p-term surface list [-w <id>] [-t <id>] [-f]                                              # List surface UUIDs in tab (-f = focused only).
    p-term surface focus [-w <id>] [-t <id>] [-s <id>] [-i <cmd>]                         # Focus surface.
    p-term surface split [-w <id>] [-t <id>] [-s <id>] [-i <cmd>] [-d h|v] [-n <uuid>]    # Split (prints UUID to stdout).
    p-term surface close [-w <id>] [-t <id>] [-s <id>]                                     # Close surface.
    ```

    ### Repository

    ```
    p-term repo list                                                     # List repository IDs.
    p-term repo open <path>                                              # Open repository.
    p-term repo worktree-new [-r <id>] [--branch <name>] [--base <ref>] [--fetch] [--name <folder>] [--location <dir>]  # Create worktree.
    ```

    ### Settings

    ```
    p-term settings [<section>]        # Open settings (general|notifications|worktrees|developer|shortcuts|updates|github).
    p-term settings repo [-r <id>]     # Open repository settings.
    ```

    ### Socket

    ```
    p-term socket                      # List active socket paths.
    ```

    ## Flag Reference

    | Flag | Short | Default | Description |
    |------|-------|---------|-------------|
    | `--worktree` | `-w` | `$P_TERM_WORKTREE_ID` | Worktree ID. |
    | `--tab` | `-t` | `$P_TERM_TAB_ID` | Tab UUID. |
    | `--surface` | `-s` | `$P_TERM_SURFACE_ID` | Surface UUID. |
    | `--script` | `-c` | — | Script UUID (for `worktree run`/`stop`). |
    | `--repo` | `-r` | `$P_TERM_REPO_ID` | Repository ID. |
    | `--input` | `-i` | — | Command to run in the terminal. |
    | `--direction` | `-d` | `horizontal` | Split direction (`horizontal`/`h` or `vertical`/`v`). |
    | `--id` | `-n` | random | UUID for new tab/surface. |
    """

  // MARK: - Codex.

  // Codex uses SKILL.md (with frontmatter) + AGENTS.md.
  static let codexSkillMd = """
    ---
    name: \(skillName)
    description: \(description)
    version: 1.0.0
    ---

    # p/term CLI

    Control p/term from the terminal. The `p-term` command is available in all p/term terminal sessions.

    ## CRITICAL: ID Tracking

    **NEVER call `p-term tab new` or `p-term surface split` without capturing
    the output.** They print the new UUID to stdout. Without it you cannot target
    the resource afterward.

    **NEVER omit `-t`/`-s` when targeting a created resource.** The env vars point
    to your own shell, not to anything you created.

    For new tabs, surface ID = tab ID.

    ### Correct:

    ```sh
    TAB_ID=$(p-term tab new -i "npm start")
    SPLIT_ID=$(p-term surface split -t "$TAB_ID" -s "$TAB_ID" -d v -i "npm test")
    p-term surface close -t "$TAB_ID" -s "$SPLIT_ID"
    p-term tab close -t "$TAB_ID"
    ```

    ### WRONG:

    ```sh
    p-term tab new -i "npm start"           # BAD: not captured
    p-term surface split -d v -i "test"     # BAD: missing -t/-s, targets your shell
    ```

    ## Commands

    - `p-term worktree [list [-f]|focus|run [-c]|stop [-c]|script list|archive|unarchive|delete|pin|unpin] [-w <id>]`
    - `p-term tab [list [-w] [-f]|focus|new|close] [-w <id>] [-t <id>] [-i <cmd>] [-n <uuid>]`
    - `p-term surface [list [-w] [-t] [-f]|focus|split|close] [-w <id>] [-t <id>] [-s <id>] [-i <cmd>] [-d h|v] [-n <uuid>]`
    - `p-term repo [list | open <path> | worktree-new [-r <id>] [--branch] [--base] [--fetch] [--name] [--location]]`
    - `p-term settings [<section>]`
    - `p-term socket`

    `list` outputs one ID per line (percent-encoded for worktrees/repos, UUIDs for tabs/surfaces).
    `worktree script list` outputs tab-separated `<uuid>\\t<kind>\\t<displayName>` rows; running scripts are ANSI-underlined.
    Use these IDs directly as `-w`, `-t`, `-s`, `-r`, `-c` flag values.

    Flags: `-w` (worktree), `-t` (tab), `-s` (surface), `-r` (repo), `-c` (script UUID for `worktree run`/`stop`), `-i` (input), `-d` (direction), `-n` (new ID).
    Env var defaults only target your own shell session. Pass explicit IDs for created resources.
    """

  static let codexAgentsMd = """
    # p/term CLI

    \(description)

    ## CRITICAL: ID Tracking

    **NEVER call `p-term tab new` or `p-term surface split` without capturing
    the output.** They print the new UUID to stdout. Without it you cannot target
    the resource afterward.

    **NEVER omit `-t`/`-s` when targeting a created resource.** The env vars point
    to your own shell, not to anything you created.

    For new tabs, surface ID = tab ID.

    ### Correct:

    ```sh
    TAB_ID=$(p-term tab new -i "npm start")
    SPLIT_ID=$(p-term surface split -t "$TAB_ID" -s "$TAB_ID" -d v -i "npm test")
    p-term surface close -t "$TAB_ID" -s "$SPLIT_ID"
    p-term tab close -t "$TAB_ID"
    ```

    ### WRONG:

    ```sh
    p-term tab new -i "npm start"           # BAD: not captured
    p-term surface split -d v -i "test"     # BAD: missing -t/-s, targets your shell
    ```

    Flags: `-w` (worktree), `-t` (tab), `-s` (surface), `-r` (repo), `-c` (script UUID for `worktree run`/`stop`), `-i` (input), `-d` (direction), `-n` (new ID).
    Env var defaults only target your own shell session. Pass explicit IDs for created resources.
    """

  // MARK: - Kiro.

  // Kiro uses SKILL.md with YAML frontmatter (same as Codex).
  static let kiroSkillMd = """
    ---
    name: \(skillName)
    description: \(description)
    ---

    # p/term CLI

    Control p/term from the terminal. The `p-term` command is available in all p/term terminal sessions.

    ## CRITICAL: ID Tracking

    **NEVER call `p-term tab new` or `p-term surface split` without capturing
    the output.** They print the new UUID to stdout. Without it you cannot target
    the resource afterward.

    **NEVER omit `-t`/`-s` when targeting a created resource.** The env vars point
    to your own shell, not to anything you created.

    For new tabs, surface ID = tab ID.

    ### Correct:

    ```sh
    TAB_ID=$(p-term tab new -i "npm start")
    SPLIT_ID=$(p-term surface split -t "$TAB_ID" -s "$TAB_ID" -d v -i "npm test")
    p-term surface close -t "$TAB_ID" -s "$SPLIT_ID"
    p-term tab close -t "$TAB_ID"
    ```

    ### WRONG:

    ```sh
    p-term tab new -i "npm start"           # BAD: not captured
    p-term surface split -d v -i "test"     # BAD: missing -t/-s, targets your shell
    ```

    ## Commands

    - `p-term worktree [list [-f]|focus|run [-c]|stop [-c]|script list|archive|unarchive|delete|pin|unpin] [-w <id>]`
    - `p-term tab [list [-w] [-f]|focus|new|close] [-w <id>] [-t <id>] [-i <cmd>] [-n <uuid>]`
    - `p-term surface [list [-w] [-t] [-f]|focus|split|close] [-w <id>] [-t <id>] [-s <id>] [-i <cmd>] [-d h|v] [-n <uuid>]`
    - `p-term repo [list | open <path> | worktree-new [-r <id>] [--branch] [--base] [--fetch] [--name] [--location]]`
    - `p-term settings [<section>]`
    - `p-term socket`

    `list` outputs one ID per line (percent-encoded for worktrees/repos, UUIDs for tabs/surfaces).
    `worktree script list` outputs tab-separated `<uuid>\\t<kind>\\t<displayName>` rows; running scripts are ANSI-underlined.
    Use these IDs directly as `-w`, `-t`, `-s`, `-r`, `-c` flag values.

    Flags: `-w` (worktree), `-t` (tab), `-s` (surface), `-r` (repo), `-c` (script UUID for `worktree run`/`stop`), `-i` (input), `-d` (direction), `-n` (new ID).
    Env var defaults only target your own shell session. Pass explicit IDs for created resources.
    """

  // MARK: - Kimi.

  // Kimi uses SKILL.md with YAML frontmatter (same structure as Kiro/Codex).
  // Discovered from `~/.kimi/skills/<name>/SKILL.md`.
  static let kimiSkillMd = """
    ---
    name: \(skillName)
    description: \(description)
    ---

    # p/term CLI

    Control p/term from the terminal. The `p-term` command is available in all p/term terminal sessions.

    ## CRITICAL: ID Tracking

    **NEVER call `p-term tab new` or `p-term surface split` without capturing
    the output.** They print the new UUID to stdout. Without it you cannot target
    the resource afterward.

    **NEVER omit `-t`/`-s` when targeting a created resource.** The env vars point
    to your own shell, not to anything you created.

    For new tabs, surface ID = tab ID.

    ### Correct:

    ```sh
    TAB_ID=$(p-term tab new -i "npm start")
    SPLIT_ID=$(p-term surface split -t "$TAB_ID" -s "$TAB_ID" -d v -i "npm test")
    p-term surface close -t "$TAB_ID" -s "$SPLIT_ID"
    p-term tab close -t "$TAB_ID"
    ```

    ### WRONG:

    ```sh
    p-term tab new -i "npm start"           # BAD: not captured
    p-term surface split -d v -i "test"     # BAD: missing -t/-s, targets your shell
    ```

    ## Commands

    - `p-term worktree [list [-f]|focus|run [-c]|stop [-c]|script list|archive|unarchive|delete|pin|unpin] [-w <id>]`
    - `p-term tab [list [-w] [-f]|focus|new|close] [-w <id>] [-t <id>] [-i <cmd>] [-n <uuid>]`
    - `p-term surface [list [-w] [-t] [-f]|focus|split|close] [-w <id>] [-t <id>] [-s <id>] [-i <cmd>] [-d h|v] [-n <uuid>]`
    - `p-term repo [list | open <path> | worktree-new [-r <id>] [--branch] [--base] [--fetch] [--name] [--location]]`
    - `p-term settings [<section>]`
    - `p-term socket`

    `list` outputs one ID per line (percent-encoded for worktrees/repos, UUIDs for tabs/surfaces).
    `worktree script list` outputs tab-separated `<uuid>\\t<kind>\\t<displayName>` rows; running scripts are ANSI-underlined.
    Use these IDs directly as `-w`, `-t`, `-s`, `-r`, `-c` flag values.

    Flags: `-w` (worktree), `-t` (tab), `-s` (surface), `-r` (repo), `-c` (script UUID for `worktree run`/`stop`), `-i` (input), `-d` (direction), `-n` (new ID).
    Env var defaults only target your own shell session. Pass explicit IDs for created resources.
    """

  // MARK: - Pi.

  // Pi uses SKILL.md with YAML frontmatter (same structure as Kiro).
  static let piSkillMd = """
    ---
    name: \(skillName)
    description: \(description)
    ---

    # p/term CLI

    Control p/term from the terminal. The `p-term` command is available in all p/term terminal sessions.

    ## CRITICAL: ID Tracking

    **NEVER call `p-term tab new` or `p-term surface split` without capturing
    the output.** They print the new UUID to stdout. Without it you cannot target
    the resource afterward.

    **NEVER omit `-t`/`-s` when targeting a created resource.** The env vars point
    to your own shell, not to anything you created.

    For new tabs, surface ID = tab ID.

    ### Correct:

    ```sh
    TAB_ID=$(p-term tab new -i "npm start")
    SPLIT_ID=$(p-term surface split -t "$TAB_ID" -s "$TAB_ID" -d v -i "npm test")
    p-term surface close -t "$TAB_ID" -s "$SPLIT_ID"
    p-term tab close -t "$TAB_ID"
    ```

    ### WRONG:

    ```sh
    p-term tab new -i "npm start"           # BAD: not captured
    p-term surface split -d v -i "test"     # BAD: missing -t/-s, targets your shell
    ```

    ## Commands

    - `p-term worktree [list [-f]|focus|run [-c]|stop [-c]|script list|archive|unarchive|delete|pin|unpin] [-w <id>]`
    - `p-term tab [list [-w] [-f]|focus|new|close] [-w <id>] [-t <id>] [-i <cmd>] [-n <uuid>]`
    - `p-term surface [list [-w] [-t] [-f]|focus|split|close] [-w <id>] [-t <id>] [-s <id>] [-i <cmd>] [-d h|v] [-n <uuid>]`
    - `p-term repo [list | open <path> | worktree-new [-r <id>] [--branch] [--base] [--fetch] [--name] [--location]]`
    - `p-term settings [<section>]`
    - `p-term socket`

    `list` outputs one ID per line (percent-encoded for worktrees/repos, UUIDs for tabs/surfaces).
    `worktree script list` outputs tab-separated `<uuid>\\t<kind>\\t<displayName>` rows; running scripts are ANSI-underlined.
    Use these IDs directly as `-w`, `-t`, `-s`, `-r`, `-c` flag values.

    Flags: `-w` (worktree), `-t` (tab), `-s` (surface), `-r` (repo), `-c` (script UUID for `worktree run`/`stop`), `-i` (input), `-d` (direction), `-n` (new ID).
    Env var defaults only target your own shell session. Pass explicit IDs for created resources.
    """
  // MARK: - OpenCode.

  // OpenCode uses SKILL.md with YAML frontmatter (same structure as Kiro).
  static let opencodeSkillMd = """
    ---
    name: \(skillName)
    description: \(description)
    ---

    # p/term CLI

    Control p/term from the terminal. The `p-term` command is available in all p/term terminal sessions.

    ## CRITICAL: ID Tracking

    **NEVER call `p-term tab new` or `p-term surface split` without capturing
    the output.** They print the new UUID to stdout. Without it you cannot target
    the resource afterward.

    **NEVER omit `-t`/`-s` when targeting a created resource.** The env vars point
    to your own shell, not to anything you created.

    For new tabs, surface ID = tab ID.

    ### Correct:

    ```sh
    TAB_ID=$(p-term tab new -i "npm start")
    SPLIT_ID=$(p-term surface split -t "$TAB_ID" -s "$TAB_ID" -d v -i "npm test")
    p-term surface close -t "$TAB_ID" -s "$SPLIT_ID"
    p-term tab close -t "$TAB_ID"
    ```

    ### WRONG:

    ```sh
    p-term tab new -i "npm start"           # BAD: not captured
    p-term surface split -d v -i "test"     # BAD: missing -t/-s, targets your shell
    ```

    ## Commands

    - `p-term worktree [list [-f]|focus|run [-c]|stop [-c]|script list|archive|unarchive|delete|pin|unpin] [-w <id>]`
    - `p-term tab [list [-w] [-f]|focus|new|close] [-w <id>] [-t <id>] [-i <cmd>] [-n <uuid>]`
    - `p-term surface [list [-w] [-t] [-f]|focus|split|close] [-w <id>] [-t <id>] [-s <id>] [-i <cmd>] [-d h|v] [-n <uuid>]`
    - `p-term repo [list | open <path> | worktree-new [-r <id>] [--branch] [--base] [--fetch] [--name] [--location]]`
    - `p-term settings [<section>]`
    - `p-term socket`

    `list` outputs one ID per line (percent-encoded for worktrees/repos, UUIDs for tabs/surfaces).
    `worktree script list` outputs tab-separated `<uuid>\\t<kind>\\t<displayName>` rows; running scripts are ANSI-underlined.
    Use these IDs directly as `-w`, `-t`, `-s`, `-r`, `-c` flag values.

    Flags: `-w` (worktree), `-t` (tab), `-s` (surface), `-r` (repo), `-c` (script UUID for `worktree run`/`stop`), `-i` (input), `-d` (direction), `-n` (new ID).
    Env var defaults only target your own shell session. Pass explicit IDs for created resources.
    """

  // MARK: - Copilot.

  // Generic CLI doc, same as OpenCode's (content is agent-agnostic).
  static let copilotSkillMd = opencodeSkillMd

}
