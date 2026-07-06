/// Hook events emitted via the JSON envelope path. Activity events
/// (`busy`, `awaitingInput`, `idle`) are atomic state-set. Each fires
/// the corresponding (surface, agent) activity directly; repeated events
/// are idempotent. The notification leg is composed in alongside an
/// envelope by `compositeCommand(forwardStdinAsNotification:)`.
nonisolated enum HookEvent: String {
  case sessionStart = "session_start"
  case sessionEnd = "session_end"
  case busy
  case awaitingInput = "awaiting_input"
  case idle
}

nonisolated enum AgentHookSettingsCommand {
  /// Sentinel comment appended to every prjct-installed hook command.
  /// `AgentHookCommandOwnership` uses this (and ONLY this) to identify
  /// managed commands. `P_TERM_SOCKET_PATH` is documented public API
  /// (CLI skill env table, Pi extension example, deeplink reference), so
  /// matching on the env-var name alone would silently strip user-authored
  /// hooks that legitimately reference it.
  static let ownershipMarker = "# p-term-managed-hook"

  /// Documented public env var. Used as ONE half of the legacy CLI-shim
  /// fingerprint (paired with `p-term integration event`); never matched
  /// alone. User-authored hooks reference it legitimately.
  static let socketPathEnvVar = "P_TERM_SOCKET_PATH"

  /// Markers present in legacy prjct hook commands (pre-socket).
  static let legacyCLIPathEnvVar = "P_TERM_CLI_PATH"
  static let legacyAgentHookMarker = "agent-hook"

  /// Verbatim 4-var presence-guard at the head of every prjct-installed
  /// hook. Carried forward unchanged across every command-shape revision,
  /// so it doubles as the pre-sentinel legacy fingerprint. A user-authored
  /// hook following the documented `P_TERM_SOCKET_PATH`-only pattern
  /// (single-var check) does not match. A user who copied this guard
  /// verbatim AND removed the trailing sentinel intentionally would be
  /// treated as legacy. That's the deliberate trade for catching every
  /// pre-envelope shape of older prjct hook.
  static let envCheck =
    #"[ -n "${P_TERM_SOCKET_PATH:-}" ]"#
    + #" && [ -n "${P_TERM_WORKTREE_ID:-}" ]"#
    + #" && [ -n "${P_TERM_TAB_ID:-}" ]"#
    + #" && [ -n "${P_TERM_SURFACE_ID:-}" ]"#

  /// Composes the OSC 3008 hook command: one guard, then (once that passes) the
  /// tty resolve plus a presence emit per event and/or a notify emit, all in a
  /// single brace group whose output is suppressed. Guarding first keeps the
  /// command truly inert outside prjct (no `ps` runs when the surface id is
  /// unset). The precondition rejects a no-op invocation that would emit nothing.
  static func compositeCommand(
    events: [HookEvent],
    forwardStdinAsNotification: Bool,
    agent: SkillAgent
  ) -> String {
    precondition(
      !events.isEmpty || forwardStdinAsNotification,
      "compositeCommand needs at least one side-effect (events or stdin forward).",
    )
    var steps: [String] = [AgentPresenceOSC.ttyResolveSnippet]
    steps += events.map { AgentPresenceOSC.emitShell(event: $0, agent: agent) }
    if forwardStdinAsNotification { steps.append(AgentPresenceOSC.emitNotifyShell(agent: agent)) }
    return "\(oscGuardExpr) && { \(steps.joined(separator: "; ")); } >/dev/null 2>&1 || true \(ownershipMarker)"
  }

  /// Guard for the OSC command: a surface id present (the no-op-outside-prjct
  /// gate). Fires both locally and over SSH; the pid suffix inside the presence
  /// emit is what's gated on the socket path, not the emission itself.
  private static var oscGuardExpr: String {
    #"[ -n "${\#(AgentPresenceOSC.surfaceEnvVar):-}" ]"#
  }
}
