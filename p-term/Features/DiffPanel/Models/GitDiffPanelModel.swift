import AppKit
import Foundation
import Observation

@Observable
final class GitDiffPanelModel {
  enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case indexLocked
    case failed
  }

  let worktreeURL: URL
  let sourcePaneID: UUID
  private let gitClient: GitClient

  var document = GitDiffDocument(files: [])
  var loadState: LoadState = .idle
  var selectedFileID: GitDiffFile.ID?

  init(worktreeURL: URL, sourcePaneID: UUID, gitClient: GitClient = GitClient()) {
    self.worktreeURL = worktreeURL
    self.sourcePaneID = sourcePaneID
    self.gitClient = gitClient
  }

  var selectedFile: GitDiffFile? {
    guard let selectedFileID else {
      return document.files.first
    }
    return document.files.first { $0.id == selectedFileID } ?? document.files.first
  }

  var hasSelection: Bool {
    selectedFile != nil
  }

  var selectedFileURL: URL? {
    guard let path = selectedFile?.displayPath else { return nil }
    return worktreeURL.appending(path: path)
  }

  var canOpenSelectedFile: Bool {
    guard let url = selectedFileURL, selectedFile?.status != .deleted else { return false }
    return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
  }

  func refresh() async {
    loadState = .loading
    let diffText: String
    switch await gitClient.diffTextResult(at: worktreeURL) {
    case .loaded(let loadedDiffText):
      diffText = loadedDiffText
    case .indexLocked:
      document = GitDiffDocument(files: [])
      selectedFileID = nil
      loadState = .indexLocked
      return
    case .failed:
      document = GitDiffDocument(files: [])
      selectedFileID = nil
      loadState = .failed
      return
    }

    let parsedDocument = GitDiffParser.parse(diffText)
    document = parsedDocument
    if let selectedFileID, parsedDocument.files.contains(where: { $0.id == selectedFileID }) {
      self.selectedFileID = selectedFileID
    } else {
      selectedFileID = parsedDocument.files.first?.id
    }
    loadState = .loaded
  }

  func selectFile(_ file: GitDiffFile) {
    selectedFileID = file.id
  }

  func copySelectedFilePath() {
    guard let path = selectedFile?.displayPath else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(path, forType: .string)
  }

  func openSelectedFile() {
    guard let url = selectedFileURL, canOpenSelectedFile else { return }
    NSWorkspace.shared.open(url)
  }

  func revealSelectedFile() {
    guard let url = selectedFileURL else { return }
    if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      NSWorkspace.shared.activateFileViewerSelecting([worktreeURL])
    }
  }
}
