import Foundation

struct GitDiffDocument: Equatable, Sendable {
  var files: [GitDiffFile]

  var isEmpty: Bool {
    files.isEmpty
  }

  var totalAddedLines: Int {
    files.reduce(0) { $0 + $1.addedLines }
  }

  var totalRemovedLines: Int {
    files.reduce(0) { $0 + $1.removedLines }
  }

  var changedFileCount: Int {
    files.count
  }
}

struct GitDiffFile: Identifiable, Equatable, Sendable {
  enum Status: Equatable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case binary
  }

  var id: String { newPath ?? oldPath ?? header }

  var header: String
  var oldPath: String?
  var newPath: String?
  var status: Status
  var metadataLines: [String]
  var hunks: [GitDiffHunk]
  var isBinary: Bool

  var displayPath: String {
    newPath ?? oldPath ?? header.removingDiffHeaderPrefix()
  }

  var addedLines: Int {
    hunks.reduce(0) { total, hunk in
      total + hunk.lines.filter { $0.kind == .addition }.count
    }
  }

  var removedLines: Int {
    hunks.reduce(0) { total, hunk in
      total + hunk.lines.filter { $0.kind == .deletion }.count
    }
  }
}

private extension String {
  func removingDiffHeaderPrefix() -> String {
    let prefix = "diff --git "
    guard starts(with: prefix) else { return self }
    return String(dropFirst(prefix.count))
  }
}

struct GitDiffHunk: Identifiable, Equatable, Sendable {
  var id = UUID()
  var header: String
  var oldStartLine: Int
  var oldLineCount: Int
  var newStartLine: Int
  var newLineCount: Int
  var lines: [GitDiffLine]

  static func == (lhs: GitDiffHunk, rhs: GitDiffHunk) -> Bool {
    lhs.header == rhs.header
      && lhs.oldStartLine == rhs.oldStartLine
      && lhs.oldLineCount == rhs.oldLineCount
      && lhs.newStartLine == rhs.newStartLine
      && lhs.newLineCount == rhs.newLineCount
      && lhs.lines == rhs.lines
  }
}

struct GitDiffLine: Identifiable, Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case context
    case addition
    case deletion
    case note
  }

  var id = UUID()
  var kind: Kind
  var oldLineNumber: Int?
  var newLineNumber: Int?
  var text: String

  static func == (lhs: GitDiffLine, rhs: GitDiffLine) -> Bool {
    lhs.kind == rhs.kind
      && lhs.oldLineNumber == rhs.oldLineNumber
      && lhs.newLineNumber == rhs.newLineNumber
      && lhs.text == rhs.text
  }
}
