import Testing

import Foundation
import PTermSettingsShared

@testable import p_term

struct GitDiffParserTests {
  @Test func parsesFileHeadersHunksAndChangedLines() {
    let diff = """
      diff --git a/Sources/App.swift b/Sources/App.swift
      index 1111111..2222222 100644
      --- a/Sources/App.swift
      +++ b/Sources/App.swift
      @@ -1,3 +1,4 @@
       import SwiftUI
      -let title = "Old"
      +let title = "New"
      +let subtitle = "Panel"
       print(title)

      """

    let document = GitDiffParser.parse(diff)

    #expect(document.files.count == 1)
    #expect(document.totalAddedLines == 2)
    #expect(document.totalRemovedLines == 1)
    let file = document.files[0]
    #expect(file.displayPath == "Sources/App.swift")
    #expect(file.status == .modified)
    #expect(file.hunks.count == 1)
    #expect(file.hunks[0].oldStartLine == 1)
    #expect(file.hunks[0].newStartLine == 1)
    #expect(file.hunks[0].lines.map(\.kind) == [.context, .deletion, .addition, .addition, .context])
    #expect(file.hunks[0].lines[1].oldLineNumber == 2)
    #expect(file.hunks[0].lines[2].newLineNumber == 2)
    #expect(file.hunks[0].lines[2].text == #"let title = "New""#)
  }

  @Test func treatsFileHeaderMarkersAsMetadataNotChangedLines() {
    let diff = """
      diff --git a/New.swift b/New.swift
      new file mode 100644
      index 0000000..2222222
      --- /dev/null
      +++ b/New.swift
      @@ -0,0 +1,2 @@
      +let value = 1
      +let other = 2

      """

    let document = GitDiffParser.parse(diff)

    #expect(document.totalAddedLines == 2)
    #expect(document.totalRemovedLines == 0)
    let file = document.files[0]
    #expect(file.status == .added)
    #expect(file.oldPath == nil)
    #expect(file.newPath == "New.swift")
    #expect(file.metadataLines.contains("--- /dev/null"))
    #expect(file.metadataLines.contains("+++ b/New.swift"))
  }

  @Test func parsesDeletedFileAndNoTrailingNewlineNote() {
    let diff = """
      diff --git a/Old.swift b/Old.swift
      deleted file mode 100644
      index 1111111..0000000
      --- a/Old.swift
      +++ /dev/null
      @@ -1 +0,0 @@
      -let stale = true
      \\ No newline at end of file

      """

    let document = GitDiffParser.parse(diff)

    let file = document.files[0]
    #expect(file.status == .deleted)
    #expect(file.oldPath == "Old.swift")
    #expect(file.newPath == nil)
    #expect(document.totalRemovedLines == 1)
    #expect(file.hunks[0].lines.map(\.kind) == [.deletion, .note])
  }

  @Test func parsesRenamedAndBinaryFiles() {
    let diff = """
      diff --git a/OldName.swift b/NewName.swift
      similarity index 91%
      rename from OldName.swift
      rename to NewName.swift
      --- a/OldName.swift
      +++ b/NewName.swift
      @@ -1 +1 @@
      -let name = "old"
      +let name = "new"
      diff --git a/image.png b/image.png
      index 1111111..2222222 100644
      Binary files a/image.png and b/image.png differ

      """

    let document = GitDiffParser.parse(diff)

    #expect(document.files.count == 2)
    #expect(document.files[0].status == .renamed)
    #expect(document.files[0].oldPath == "OldName.swift")
    #expect(document.files[0].newPath == "NewName.swift")
    #expect(document.files[1].status == .binary)
    #expect(document.files[1].isBinary)
  }

  @Test func parsesDiffHeaderPathsContainingSpaces() {
    let diff = """
      diff --git a/Source Files/Old Name.swift b/Source Files/New Name.swift
      similarity index 91%
      rename from Source Files/Old Name.swift
      rename to Source Files/New Name.swift
      --- a/Source Files/Old Name.swift
      +++ b/Source Files/New Name.swift
      @@ -1 +1 @@
      -let name = "old"
      +let name = "new"

      """

    let document = GitDiffParser.parse(diff)

    let file = document.files[0]
    #expect(file.oldPath == "Source Files/Old Name.swift")
    #expect(file.newPath == "Source Files/New Name.swift")
    #expect(file.displayPath == "Source Files/New Name.swift")
  }
}

struct GitClientDiffTextTests {
  @Test func appendsUntrackedFileDiffs() async {
    let worktreeURL = URL(fileURLWithPath: "/tmp/prjct-git-diff-test")
    let trackedDiff = """
      diff --git a/Tracked.swift b/Tracked.swift
      index 1111111..2222222 100644
      --- a/Tracked.swift
      +++ b/Tracked.swift
      @@ -1 +1 @@
      -let value = 1
      +let value = 2

      """
    let untrackedDiff = """
      diff --git a/New File.swift b/New File.swift
      new file mode 100644
      index 0000000..3333333
      --- /dev/null
      +++ b/New File.swift
      @@ -0,0 +1 @@
      +let value = 3

      """
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("ls-files") {
          return ShellOutput(stdout: "New File.swift\0", stderr: "", exitCode: 0)
        }
        if arguments.contains("--no-index") {
          throw ShellClientError(command: "git diff --no-index", stdout: untrackedDiff, stderr: "", exitCode: 1)
        }
        if arguments.contains("diff"), arguments.contains("HEAD") {
          return ShellOutput(stdout: trackedDiff, stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in
        ShellOutput(stdout: "", stderr: "", exitCode: 0)
      }
    )

    let diffText = await GitClient(shell: shell).diffText(at: worktreeURL)

    #expect(diffText?.contains("diff --git a/Tracked.swift b/Tracked.swift") == true)
    #expect(diffText?.contains("diff --git a/New File.swift b/New File.swift") == true)
  }

  @Test func usesCachedDiffWhenRepositoryHasNoHead() async {
    let worktreeURL = URL(fileURLWithPath: "/tmp/prjct-unborn-git-diff-test")
    let cachedDiff = """
      diff --git a/Staged.swift b/Staged.swift
      new file mode 100644
      index 0000000..4444444
      --- /dev/null
      +++ b/Staged.swift
      @@ -0,0 +1 @@
      +let staged = true

      """
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("rev-parse") {
          throw ShellClientError(
            command: "git rev-parse --verify HEAD",
            stdout: "",
            stderr: "bad revision",
            exitCode: 128)
        }
        if arguments.contains("ls-files") {
          return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        if arguments.contains("--cached") {
          return ShellOutput(stdout: cachedDiff, stderr: "", exitCode: 0)
        }
        if arguments.contains("HEAD") {
          return ShellOutput(stdout: "unexpected HEAD diff", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in
        ShellOutput(stdout: "", stderr: "", exitCode: 0)
      }
    )

    let diffText = await GitClient(shell: shell).diffText(at: worktreeURL)

    #expect(diffText?.contains("diff --git a/Staged.swift b/Staged.swift") == true)
    #expect(diffText?.contains("unexpected HEAD diff") == false)
  }
}
