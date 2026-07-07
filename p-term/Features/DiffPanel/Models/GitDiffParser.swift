import Foundation

enum GitDiffParser {
  static func parse(_ diffText: String) -> GitDiffDocument {
    var files: [GitDiffFile] = []
    var currentFile: FileBuilder?
    var currentHunk: HunkBuilder?
    var oldLineNumber = 0
    var newLineNumber = 0

    func flushHunk() {
      guard let hunk = currentHunk else { return }
      currentFile?.hunks.append(hunk.build())
      currentHunk = nil
    }

    func flushFile() {
      flushHunk()
      guard let file = currentFile else { return }
      files.append(file.build())
      currentFile = nil
    }

    for rawLine in diffText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
      if rawLine.starts(with: "diff --git ") {
        flushFile()
        currentFile = FileBuilder(header: rawLine)
        continue
      }

      guard currentFile != nil else {
        continue
      }

      if rawLine.starts(with: "@@") {
        flushHunk()
        let range = parseHunkRange(rawLine)
        oldLineNumber = range.oldStartLine
        newLineNumber = range.newStartLine
        currentHunk = HunkBuilder(
          header: rawLine,
          oldStartLine: range.oldStartLine,
          oldLineCount: range.oldLineCount,
          newStartLine: range.newStartLine,
          newLineCount: range.newLineCount
        )
        continue
      }

      if currentHunk != nil {
        if rawLine.starts(with: "+"), !rawLine.starts(with: "+++") {
          currentHunk?.lines.append(
            GitDiffLine(
              kind: .addition,
              oldLineNumber: nil,
              newLineNumber: newLineNumber,
              text: String(rawLine.dropFirst())
            )
          )
          newLineNumber += 1
          continue
        }

        if rawLine.starts(with: "-"), !rawLine.starts(with: "---") {
          currentHunk?.lines.append(
            GitDiffLine(
              kind: .deletion,
              oldLineNumber: oldLineNumber,
              newLineNumber: nil,
              text: String(rawLine.dropFirst())
            )
          )
          oldLineNumber += 1
          continue
        }

        if rawLine.starts(with: " ") {
          currentHunk?.lines.append(
            GitDiffLine(
              kind: .context,
              oldLineNumber: oldLineNumber,
              newLineNumber: newLineNumber,
              text: String(rawLine.dropFirst())
            )
          )
          oldLineNumber += 1
          newLineNumber += 1
          continue
        }

        if rawLine.starts(with: "\\") {
          currentHunk?.lines.append(
            GitDiffLine(kind: .note, oldLineNumber: nil, newLineNumber: nil, text: rawLine)
          )
          continue
        }
      }

      currentFile?.consumeMetadata(rawLine)
    }

    flushFile()
    return GitDiffDocument(files: files)
  }

  private static func parseHunkRange(_ line: String) -> HunkRange {
    let parts = line.split(separator: " ")
    guard parts.count >= 3 else {
      return HunkRange(oldStartLine: 0, oldLineCount: 0, newStartLine: 0, newLineCount: 0)
    }
    let oldRange = parseRangeToken(String(parts[1]), marker: "-")
    let newRange = parseRangeToken(String(parts[2]), marker: "+")
    return HunkRange(
      oldStartLine: oldRange.start,
      oldLineCount: oldRange.count,
      newStartLine: newRange.start,
      newLineCount: newRange.count
    )
  }

  private static func parseRangeToken(_ token: String, marker: Character) -> (start: Int, count: Int) {
    var trimmed = token
    if trimmed.first == marker {
      trimmed.removeFirst()
    }
    let components = trimmed.split(separator: ",", maxSplits: 1).map(String.init)
    let start = Int(components.first ?? "") ?? 0
    let count = components.count > 1 ? (Int(components[1]) ?? 1) : 1
    return (start, count)
  }
}

private struct HunkRange {
  var oldStartLine: Int
  var oldLineCount: Int
  var newStartLine: Int
  var newLineCount: Int
}

private struct FileBuilder {
  var header: String
  var oldPath: String?
  var newPath: String?
  var status: GitDiffFile.Status = .modified
  var metadataLines: [String] = []
  var hunks: [GitDiffHunk] = []
  var isBinary = false

  init(header: String) {
    self.header = header
    let paths = Self.paths(fromDiffHeader: header)
    oldPath = paths.oldPath
    newPath = paths.newPath
  }

  mutating func consumeMetadata(_ line: String) {
    metadataLines.append(line)

    if line.starts(with: "--- ") {
      oldPath = normalizedPath(String(line.dropFirst(4)))
      if oldPath == nil {
        status = .added
      }
      return
    }

    if line.starts(with: "+++ ") {
      newPath = normalizedPath(String(line.dropFirst(4)))
      if newPath == nil {
        status = .deleted
      } else if oldPath == nil {
        status = .added
      }
      return
    }

    if line.starts(with: "new file mode") {
      status = .added
    } else if line.starts(with: "deleted file mode") {
      status = .deleted
    } else if line.starts(with: "rename from ") {
      status = .renamed
      oldPath = String(line.dropFirst("rename from ".count))
    } else if line.starts(with: "rename to ") {
      status = .renamed
      newPath = String(line.dropFirst("rename to ".count))
    } else if line.starts(with: "copy from ") {
      status = .copied
      oldPath = String(line.dropFirst("copy from ".count))
    } else if line.starts(with: "copy to ") {
      status = .copied
      newPath = String(line.dropFirst("copy to ".count))
    } else if line.starts(with: "Binary files ") || line.starts(with: "GIT binary patch") {
      status = .binary
      isBinary = true
    }
  }

  func build() -> GitDiffFile {
    GitDiffFile(
      header: header,
      oldPath: oldPath,
      newPath: newPath,
      status: isBinary ? .binary : status,
      metadataLines: metadataLines,
      hunks: hunks,
      isBinary: isBinary
    )
  }

  private func normalizedPath(_ path: String) -> String? {
    let trimmed = path.trimmingCharacters(in: .whitespaces)
    guard trimmed != "/dev/null" else { return nil }
    if trimmed.starts(with: "a/") || trimmed.starts(with: "b/") {
      return String(trimmed.dropFirst(2))
    }
    return trimmed
  }

  private static func paths(fromDiffHeader header: String) -> (oldPath: String?, newPath: String?) {
    let prefix = "diff --git "
    guard header.starts(with: prefix) else {
      return (nil, nil)
    }
    let parts = header.dropFirst(prefix.count).split(separator: " ", maxSplits: 1).map(String.init)
    guard parts.count == 2 else {
      return (nil, nil)
    }
    return (normalizedPathPart(parts[0]), normalizedPathPart(parts[1]))
  }

  private static func normalizedPathPart(_ path: String) -> String? {
    guard path != "/dev/null" else { return nil }
    if path.starts(with: "a/") || path.starts(with: "b/") {
      return String(path.dropFirst(2))
    }
    return path
  }
}

private struct HunkBuilder {
  var header: String
  var oldStartLine: Int
  var oldLineCount: Int
  var newStartLine: Int
  var newLineCount: Int
  var lines: [GitDiffLine] = []

  func build() -> GitDiffHunk {
    GitDiffHunk(
      header: header,
      oldStartLine: oldStartLine,
      oldLineCount: oldLineCount,
      newStartLine: newStartLine,
      newLineCount: newLineCount,
      lines: lines
    )
  }
}
