nonisolated enum AgentHookCommandOwnership {
  /// True when the command was installed by p/term. The trailing
  /// sentinel is the source of truth; legacy patterns cover hooks from
  /// versions before the sentinel existed.
  static func isPTermManagedCommand(_ command: String?) -> Bool {
    guard let command else { return false }
    if command.contains(AgentHookSettingsCommand.ownershipMarker) { return true }
    return isLegacyCommand(command)
  }

  /// True for pre-sentinel p/term hooks. Current commands carry the
  /// sentinel and are NOT legacy.
  static func isLegacyCommand(_ command: String) -> Bool {
    guard !command.contains(AgentHookSettingsCommand.ownershipMarker) else { return false }
    if command.contains(AgentHookSettingsCommand.legacyCLIPathEnvVar)
      && command.contains(AgentHookSettingsCommand.legacyAgentHookMarker)
    {
      return true
    }
    if command.contains(AgentHookSettingsCommand.socketPathEnvVar)
      && command.contains(#"p-term integration event"#)
    {
      return true
    }
    // Pre-envelope hooks carry the verbatim 4-var presence-guard but
    // neither the sentinel nor the CLI shim. The guard is a p/term-
    // specific fingerprint: a user following the documented single-var
    // `P_TERM_SOCKET_PATH` pattern won't match. See `envCheck` for the
    // deliberate trade w.r.t. customized-body-with-p/term-head hooks.
    return command.contains(AgentHookSettingsCommand.envCheck)
  }
}
