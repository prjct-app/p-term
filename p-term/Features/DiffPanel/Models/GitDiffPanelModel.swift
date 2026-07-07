import AppKit
import Foundation
import Observation

@Observable
final class GitDiffPanelModel {
  enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case unavailable
  }

  let worktreeURL: URL
  private let gitClient: GitClient

  var document = GitDiffDocument(files: [])
  var loadState: LoadState = .idle
  var selectedFileID: GitDiffFile.ID?

  init(worktreeURL: URL, gitClient: GitClient = GitClient()) {
    self.worktreeURL = worktreeURL
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

  func refresh() async {
    loadState = .loading
    guard let diffText = await gitClient.diffText(at: worktreeURL) else {
      document = GitDiffDocument(files: [])
      selectedFileID = nil
      loadState = .unavailable
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
}
