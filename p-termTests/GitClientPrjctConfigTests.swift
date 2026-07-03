import Foundation
import Testing

@testable import p_term

struct GitClientPrjctConfigTests {
  private func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "pterm-prjct-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func configURL(in root: URL) -> URL {
    root.appending(path: ".prjct", directoryHint: .isDirectory)
      .appending(path: "prjct.config.json", directoryHint: .notDirectory)
  }

  private func writeConfig(_ contents: String, in root: URL) throws {
    let directory = root.appending(path: ".prjct", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try contents.write(to: configURL(in: root), atomically: true, encoding: .utf8)
  }

  @Test func propagatesConfigWhenRepoIsPrjctProject() throws {
    let repoRoot = makeTempDirectory()
    let worktree = makeTempDirectory()
    defer {
      try? FileManager.default.removeItem(at: repoRoot)
      try? FileManager.default.removeItem(at: worktree)
    }
    // Same projectId link → the worktree shares the repo's prjct memory.
    let payload = #"{"projectId":"abc123","persona":"code"}"#
    try writeConfig(payload, in: repoRoot)

    GitClient.propagatePrjctConfig(from: repoRoot, to: worktree)

    let copied = try String(contentsOf: configURL(in: worktree), encoding: .utf8)
    #expect(copied == payload)
  }

  @Test func isNoOpWhenRepoIsNotPrjctProject() {
    let repoRoot = makeTempDirectory()
    let worktree = makeTempDirectory()
    defer {
      try? FileManager.default.removeItem(at: repoRoot)
      try? FileManager.default.removeItem(at: worktree)
    }

    GitClient.propagatePrjctConfig(from: repoRoot, to: worktree)

    #expect(!FileManager.default.fileExists(atPath: configURL(in: worktree).path(percentEncoded: false)))
  }

  @Test func doesNotOverwriteExistingWorktreeConfig() throws {
    let repoRoot = makeTempDirectory()
    let worktree = makeTempDirectory()
    defer {
      try? FileManager.default.removeItem(at: repoRoot)
      try? FileManager.default.removeItem(at: worktree)
    }
    try writeConfig(#"{"projectId":"repo"}"#, in: repoRoot)
    let existing = #"{"projectId":"worktree-existing"}"#
    try writeConfig(existing, in: worktree)

    GitClient.propagatePrjctConfig(from: repoRoot, to: worktree)

    let after = try String(contentsOf: configURL(in: worktree), encoding: .utf8)
    #expect(after == existing)
  }
}
