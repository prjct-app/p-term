import Testing

@testable import p_term

@MainActor
struct KnownAgentCLITests {
  @Test func matchesDistinctiveAgentTokens() {
    #expect(KnownAgentCLI.match(inTitle: "claude") == "Claude Code")
    #expect(KnownAgentCLI.match(inTitle: "codex cli") == "Codex")
    #expect(KnownAgentCLI.match(inTitle: "cursor-agent") == "Cursor")
    #expect(KnownAgentCLI.match(inTitle: "gemini") == "Gemini CLI")
    #expect(KnownAgentCLI.match(inTitle: "aider") == "Aider")
    #expect(KnownAgentCLI.match(inTitle: "opencode") == "OpenCode")
    #expect(KnownAgentCLI.match(inTitle: "goose") == "Goose")
    #expect(KnownAgentCLI.match(inTitle: "grok") == "Grok")
  }

  @Test func opencodeWinsBeforeShorterTokens() {
    // `opencode` is listed ahead of `codex`/`code`-like tokens so a title
    // containing it resolves to OpenCode, not a substring collision.
    #expect(KnownAgentCLI.match(inTitle: "opencode session") == "OpenCode")
  }

  @Test func nonAgentTitlesDoNotMatch() {
    #expect(KnownAgentCLI.match(inTitle: "zsh") == nil)
    #expect(KnownAgentCLI.match(inTitle: "vim readme.md") == nil)
    #expect(KnownAgentCLI.match(inTitle: "~/dev/project") == nil)
  }

  @Test func matchIsCaseInsensitiveViaLowercasedInput() {
    // `match` expects an already-lowercased title (its only caller lowercases).
    #expect(KnownAgentCLI.match(inTitle: "running claude code") == "Claude Code")
  }
}
