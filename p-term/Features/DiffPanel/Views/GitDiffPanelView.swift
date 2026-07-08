import SwiftUI

struct GitDiffPanelView: View {
  @State private var model: GitDiffPanelModel

  init(worktreeURL: URL, sourceDirectoryURL: URL? = nil, sourcePaneID: UUID) {
    _model = State(
      initialValue: GitDiffPanelModel(
        worktreeURL: worktreeURL,
        sourceDirectoryURL: sourceDirectoryURL,
        sourcePaneID: sourcePaneID
      ))
  }

  var body: some View {
    VStack(spacing: 0) {
      GitDiffToolbarView(model: model)
      Divider()
      HStack(spacing: 0) {
        GitDiffFileListView(model: model)
          .frame(width: AppChromeMetrics.SidePanel.diffSidebarWidth)
        Divider()
        content
      }
    }
    .background(GitDiffPalette.panelBackground)
    .task(id: model.sourcePaneID) {
      await model.refresh()
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.loadState {
    case .indexLocked:
      ContentUnavailableView(
        "Diff unavailable",
        systemImage: "exclamationmark.triangle",
        description: Text("The repository index is locked.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .failed:
      ContentUnavailableView(
        "Diff unavailable",
        systemImage: "exclamationmark.triangle",
        description: Text("Git could not load this worktree's diff.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .loaded where model.document.isEmpty:
      ContentUnavailableView(
        "No changes",
        systemImage: "checkmark.circle",
        description: Text("Nothing differs from HEAD in this worktree.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .idle where model.document.isEmpty,
      .loading where model.document.isEmpty:
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    default:
      GitDiffSelectedFileView(model: model)
    }
  }
}

private struct GitDiffFileListView: View {
  let model: GitDiffPanelModel

  var body: some View {
    List(selection: selectedFileBinding) {
      Section("Files") {
        ForEach(model.document.files) { file in
          GitDiffFileListRow(file: file)
            .tag(file.id)
        }
      }
    }
    .listStyle(.sidebar)
  }

  private var selectedFileBinding: Binding<GitDiffFile.ID?> {
    Binding(
      get: { model.selectedFileID ?? model.document.files.first?.id },
      set: { model.selectedFileID = $0 }
    )
  }
}

private struct GitDiffToolbarView: View {
  let model: GitDiffPanelModel

  var body: some View {
    NativeSidePanelHeader(
      title: "Uncommitted changes",
      subtitle: model.diffRootURL.path(percentEncoded: false)
    ) {
      Image(systemName: "arrow.left.arrow.right")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
    } accessory: {
      if model.document.changedFileCount > 0 {
        Text("\(model.document.changedFileCount)")
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 4))

        DiffStatBadge(value: model.document.totalAddedLines, kind: .addition)
        DiffStatBadge(value: model.document.totalRemovedLines, kind: .deletion)
      }
    } actions: {
      if model.loadState == .loading {
        ProgressView().controlSize(.small)
      }

      ForEach(GitDiffPanelTool.allCases) { tool in
        GitDiffToolButton(tool: tool, model: model)
      }
    }
  }
}

/// Shared view-layer styling for a file's change status, used by every place
/// that renders a status icon (the file list row, the selected-file header).
extension GitDiffFile.Status {
  fileprivate var iconName: String {
    switch self {
    case .added: "plus.square"
    case .deleted: "minus.square"
    case .renamed: "arrow.triangle.2.circlepath"
    case .copied: "doc.on.doc"
    case .binary: "doc.badge.gearshape"
    case .modified: "doc.text"
    }
  }

  fileprivate var iconColor: Color {
    switch self {
    case .added: GitDiffPalette.additionAccent
    case .deleted: GitDiffPalette.deletionAccent
    case .renamed, .copied: .orange
    case .binary: .secondary
    case .modified: .accentColor
    }
  }
}

private struct GitDiffFileListRow: View {
  let file: GitDiffFile

  var body: some View {
    Label {
      HStack(spacing: 6) {
        VStack(alignment: .leading, spacing: 1) {
          Text(file.displayPath)
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
          Text(statusText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 6)
        if file.addedLines > 0 {
          DiffStatBadge(value: file.addedLines, kind: .addition)
        }
        if file.removedLines > 0 {
          DiffStatBadge(value: file.removedLines, kind: .deletion)
        }
      }
    } icon: {
      Image(systemName: file.status.iconName)
        .font(.system(size: 12))
        .foregroundStyle(file.status.iconColor)
        .frame(width: 16)
    }
  }

  private var statusText: String {
    switch file.status {
    case .added: "Added"
    case .deleted: "Deleted"
    case .renamed: "Renamed"
    case .copied: "Copied"
    case .binary: "Binary"
    case .modified: "Modified"
    }
  }

}

private enum GitDiffPanelTool: CaseIterable, Identifiable {
  case openFile
  case revealFile
  case copyPath
  case refresh

  var id: Self { self }

  var systemImage: String {
    switch self {
    case .openFile: "arrow.up.right.square"
    case .revealFile: "folder"
    case .copyPath: "doc.on.doc"
    case .refresh: "arrow.clockwise"
    }
  }

  var help: String {
    switch self {
    case .openFile: "Open file"
    case .revealFile: "Reveal in Finder"
    case .copyPath: "Copy file path"
    case .refresh: "Refresh diff"
    }
  }

  func isEnabled(model: GitDiffPanelModel) -> Bool {
    switch self {
    case .openFile:
      model.canOpenSelectedFile
    case .revealFile, .copyPath:
      model.hasSelection
    case .refresh:
      model.loadState != .loading
    }
  }

  func perform(model: GitDiffPanelModel) {
    switch self {
    case .openFile:
      model.openSelectedFile()
    case .revealFile:
      model.revealSelectedFile()
    case .copyPath:
      model.copySelectedFilePath()
    case .refresh:
      Task { await model.refresh() }
    }
  }
}

private struct GitDiffToolButton: View {
  let tool: GitDiffPanelTool
  let model: GitDiffPanelModel

  var body: some View {
    NativeSidePanelIconButton(
      systemImage: tool.systemImage,
      help: tool.help,
      isEnabled: tool.isEnabled(model: model)
    ) {
      tool.perform(model: model)
    }
  }
}

private struct GitDiffSelectedFileView: View {
  let model: GitDiffPanelModel

  var body: some View {
    Group {
      if let file = model.selectedFile {
        ScrollView([.vertical, .horizontal]) {
          LazyVStack(alignment: .leading, spacing: 0) {
            GitDiffFileBlockHeader(file: file, isSelected: true)

            GitDiffFileHeaderView(file: file)

            if file.isBinary {
              GitDiffMetadataLine(text: "Binary file")
            }

            ForEach(file.hunks) { hunk in
              GitDiffHunkHeaderLine(text: hunk.header)
              ForEach(hunk.lines) { line in
                GitDiffCodeLine(line: line)
              }
            }
          }
          .frame(minWidth: 760, maxWidth: .infinity, alignment: .topLeading)
        }
        .background(GitDiffPalette.diffBackground)
      } else {
        ContentUnavailableView("No file selected", systemImage: "doc.text.magnifyingglass")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct GitDiffFileBlockHeader: View {
  let file: GitDiffFile
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: file.status.iconName)
        .font(.caption)
        .foregroundStyle(file.status.iconColor)
        .frame(width: 16)

      Text(file.displayPath)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(.primary)

      Spacer(minLength: 12)

      if file.addedLines > 0 {
        DiffStatBadge(value: file.addedLines, kind: .addition)
      }
      if file.removedLines > 0 {
        DiffStatBadge(value: file.removedLines, kind: .deletion)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 34)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(isSelected ? GitDiffPalette.selectedFileHeader : GitDiffPalette.fileHeader)
    .contentShape(.rect)
  }
}

private struct GitDiffFileHeaderView: View {
  let file: GitDiffFile

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      GitDiffMetadataLine(text: file.header)
      ForEach(file.metadataLines, id: \.self) { line in
        GitDiffMetadataLine(text: line)
      }
    }
  }
}

private struct GitDiffMetadataLine: View {
  let text: String

  var body: some View {
    Text(text)
      .font(diffFont)
      .foregroundStyle(GitDiffPalette.metadataText)
      .lineLimit(1)
      .padding(.horizontal, 12)
      .frame(minWidth: 760, maxWidth: .infinity, minHeight: 21, alignment: .leading)
      .background(GitDiffPalette.metadataBackground)
      .textSelection(.enabled)
  }
}

private struct GitDiffHunkHeaderLine: View {
  let text: String

  var body: some View {
    Text(text)
      .font(diffFont.weight(.semibold))
      .foregroundStyle(GitDiffPalette.hunkText)
      .lineLimit(1)
      .padding(.horizontal, 12)
      .frame(minWidth: 760, maxWidth: .infinity, minHeight: 24, alignment: .leading)
      .background(GitDiffPalette.hunkBackground)
      .textSelection(.enabled)
  }
}

private struct GitDiffCodeLine: View {
  let line: GitDiffLine

  var body: some View {
    HStack(spacing: 0) {
      Text(oldNumber)
        .frame(width: 48, alignment: .trailing)
        .foregroundStyle(lineNumberColor)
      Text(newNumber)
        .frame(width: 48, alignment: .trailing)
        .foregroundStyle(lineNumberColor)
      Text(prefix)
        .frame(width: 24, alignment: .center)
        .foregroundStyle(prefixColor)
      Text(verbatim: line.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(textColor)
    }
    .font(diffFont)
    .lineLimit(1)
    .padding(.trailing, 12)
    .frame(minWidth: 760, maxWidth: .infinity, minHeight: 21, alignment: .leading)
    .background(backgroundColor)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(edgeColor)
        .frame(width: 3)
    }
    .textSelection(.enabled)
  }

  private var oldNumber: String {
    line.oldLineNumber.map(String.init) ?? ""
  }

  private var newNumber: String {
    line.newLineNumber.map(String.init) ?? ""
  }

  private var prefix: String {
    switch line.kind {
    case .addition: "+"
    case .deletion: "-"
    case .context: " "
    case .note: "\\"
    }
  }

  private var prefixColor: Color {
    switch line.kind {
    case .addition: GitDiffPalette.additionAccent
    case .deletion: GitDiffPalette.deletionAccent
    case .context, .note: GitDiffPalette.contextText
    }
  }

  private var textColor: Color {
    switch line.kind {
    case .addition: GitDiffPalette.additionText
    case .deletion: GitDiffPalette.deletionText
    case .context: GitDiffPalette.contextText
    case .note: GitDiffPalette.metadataText
    }
  }

  private var lineNumberColor: Color {
    switch line.kind {
    case .addition: GitDiffPalette.additionText.opacity(0.72)
    case .deletion: GitDiffPalette.deletionText.opacity(0.72)
    case .context, .note: GitDiffPalette.lineNumberText
    }
  }

  private var backgroundColor: Color {
    switch line.kind {
    case .addition: GitDiffPalette.additionBackground
    case .deletion: GitDiffPalette.deletionBackground
    case .context: GitDiffPalette.contextBackground
    case .note: GitDiffPalette.metadataBackground
    }
  }

  private var edgeColor: Color {
    switch line.kind {
    case .addition: GitDiffPalette.additionAccent
    case .deletion: GitDiffPalette.deletionAccent
    case .context, .note: .clear
    }
  }
}

private struct DiffStatBadge: View {
  enum Kind {
    case addition
    case deletion
  }

  let value: Int
  let kind: Kind

  var body: some View {
    Text("\(prefix)\(value)")
      .font(.caption2.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(foregroundColor)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(backgroundColor, in: .rect(cornerRadius: 4))
  }

  private var prefix: String {
    switch kind {
    case .addition: "+"
    case .deletion: "-"
    }
  }

  private var foregroundColor: Color {
    switch kind {
    case .addition: GitDiffPalette.additionAccent
    case .deletion: GitDiffPalette.deletionAccent
    }
  }

  private var backgroundColor: Color {
    switch kind {
    case .addition: GitDiffPalette.additionBadgeBackground
    case .deletion: GitDiffPalette.deletionBadgeBackground
    }
  }
}

private enum GitDiffPalette {
  static let panelBackground = Color(nsColor: .windowBackgroundColor)
  static let diffBackground = Color(nsColor: .textBackgroundColor).opacity(0.96)
  static let fileBackground = Color(nsColor: .textBackgroundColor).opacity(0.72)
  static let fileHeader = Color.primary.opacity(0.055)
  static let selectedFileHeader = Color.accentColor.opacity(0.16)
  static let metadataBackground = Color.primary.opacity(0.035)
  static let hunkBackground = Color(red: 0.10, green: 0.12, blue: 0.20).opacity(0.78)
  static let contextBackground = Color.clear
  static let additionBackground = Color(red: 0.03, green: 0.24, blue: 0.12).opacity(0.82)
  static let deletionBackground = Color(red: 0.30, green: 0.08, blue: 0.09).opacity(0.88)
  static let additionBadgeBackground = Color(red: 0.03, green: 0.28, blue: 0.13).opacity(0.78)
  static let deletionBadgeBackground = Color(red: 0.34, green: 0.08, blue: 0.09).opacity(0.82)

  static let hunkText = Color(red: 0.70, green: 0.78, blue: 1.0)
  static let metadataText = Color.secondary.opacity(0.86)
  static let contextText = Color.primary.opacity(0.92)
  static let lineNumberText = Color.secondary.opacity(0.58)
  static let additionText = Color(red: 0.78, green: 1.0, blue: 0.82)
  static let deletionText = Color(red: 1.0, green: 0.77, blue: 0.77)
  static let additionAccent = Color(red: 0.29, green: 0.86, blue: 0.45)
  static let deletionAccent = Color(red: 1.0, green: 0.34, blue: 0.34)
}

private let diffFont = Font.system(size: 11.5, design: .monospaced)
