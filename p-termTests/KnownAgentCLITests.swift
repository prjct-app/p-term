import Testing

@testable import PTermSettingsShared
@testable import p_term

/// Locks the hook-free agent detection from the terminal title, including the
/// SkillAgent mapping that drives the real logo in the sidebar / island.
@MainActor
struct KnownAgentCLITests {
  @Test func matchesDistinctiveAgentTokens() {
    #expect(KnownAgentCLI.match(inTitle: "claude")?.name == "Claude Code")
    #expect(KnownAgentCLI.match(inTitle: "codex cli")?.name == "Codex")
    #expect(KnownAgentCLI.match(inTitle: "cursor-agent")?.name == "Cursor")
    #expect(KnownAgentCLI.match(inTitle: "gemini")?.name == "Gemini CLI")
    #expect(KnownAgentCLI.match(inTitle: "aider")?.name == "Aider")
    #expect(KnownAgentCLI.match(inTitle: "opencode")?.name == "OpenCode")
    #expect(KnownAgentCLI.match(inTitle: "goose")?.name == "Goose")
    #expect(KnownAgentCLI.match(inTitle: "grok")?.name == "Grok")
  }

  @Test func mapsToSkillAgentLogoWhenWeShipOne() {
    // These drive AgentBadgeView's real logo mark.
    #expect(KnownAgentCLI.match(inTitle: "claude")?.agent == .claude)
    #expect(KnownAgentCLI.match(inTitle: "codex cli")?.agent == .codex)
    #expect(KnownAgentCLI.match(inTitle: "opencode")?.agent == .opencode)
    #expect(KnownAgentCLI.match(inTitle: "copilot")?.agent == .copilot)
    // Recognized CLI, but no bundled logo → nil agent (generic glyph).
    #expect(KnownAgentCLI.match(inTitle: "cursor-agent")?.agent == nil)
    #expect(KnownAgentCLI.match(inTitle: "gemini")?.agent == nil)
  }

  @Test func opencodeWinsBeforeShorterTokens() {
    #expect(KnownAgentCLI.match(inTitle: "opencode session")?.name == "OpenCode")
  }

  @Test func nonAgentTitlesDoNotMatch() {
    #expect(KnownAgentCLI.match(inTitle: "zsh") == nil)
    #expect(KnownAgentCLI.match(inTitle: "vim readme.md") == nil)
    #expect(KnownAgentCLI.match(inTitle: "~/dev/project") == nil)
  }

  @Test func tokenMustBeAWholeWordNotASubstring() {
    #expect(KnownAgentCLI.match(inTitle: "precursor") == nil)
    #expect(KnownAgentCLI.match(inTitle: "codexample.ts") == nil)
    #expect(KnownAgentCLI.match(inTitle: "mongoose") == nil)
  }

  @Test func boundaryMatchStillAcceptsRealAgentInvocations() {
    #expect(KnownAgentCLI.match(inTitle: "cursor-agent")?.name == "Cursor")
    #expect(KnownAgentCLI.match(inTitle: "npx @openai/codex")?.name == "Codex")
    #expect(KnownAgentCLI.match(inTitle: "goose session start")?.name == "Goose")
    #expect(KnownAgentCLI.match(inTitle: "gemini")?.name == "Gemini CLI")
  }
}
