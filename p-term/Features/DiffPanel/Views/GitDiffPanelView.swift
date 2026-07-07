import SwiftUI

struct GitDiffPanelView: View {
  @State private var model: GitDiffPanelModel

  init(worktreeURL: URL) {
    _model = State(initialValue: GitDiffPanelModel(worktreeURL: worktreeURL))
  }

  var body: some View {
    VStack(spacing: 0) {
      GitDiffToolbarView(model: model)
      Divider()
      content
    }
    .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
    .task {
      await model.refresh()
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.loadState {
    case .unavailable:
      ContentUnavailableView(
        "Diff unavailable",
        systemImage: "exclamationmark.triangle",
        description: Text("The repository index is locked.")
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
      HStack(spacing: 0) {
        GitDiffFileSidebarView(model: model)
          .frame(width: 220)
        Divider()
        GitDiffContentView(file: model.selectedFile)
      }
    }
  }
}

private struct GitDiffToolbarView: View {
  let model: GitDiffPanelModel

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "arrow.left.arrow.right")
        .foregroundStyle(.secondary)

      Text("Diff")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

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

      Spacer(minLength: 0)

      if model.loadState == .loading {
        ProgressView().controlSize(.small)
      }

      Button {
        model.copySelectedFilePath()
      } label: {
        Image(systemName: "doc.on.doc")
      }
      .buttonStyle(.plain)
      .help("Copy file path")
      .disabled(!model.hasSelection)

      Button {
        Task { await model.refresh() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.plain)
      .help("Refresh diff")
      .disabled(model.loadState == .loading)
    }
    .padding(.horizontal, 10)
    .frame(height: 30)
  }
}

private struct GitDiffFileSidebarView: View {
  let model: GitDiffPanelModel

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 1) {
        ForEach(model.document.files) { file in
          GitDiffFileRow(
            file: file,
            isSelected: model.selectedFile?.id == file.id
          ) {
            model.selectFile(file)
          }
        }
      }
      .padding(6)
    }
    .background(Color.primary.opacity(0.025))
  }
}

private struct GitDiffFileRow: View {
  let file: GitDiffFile
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Image(systemName: iconName)
          .font(.caption)
          .foregroundStyle(iconColor)
          .frame(width: 14)

        Text(file.displayPath)
          .font(.caption)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(isSelected ? .primary : .secondary)

        Spacer(minLength: 0)

        if file.addedLines > 0 {
          Text("+\(file.addedLines)")
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.green)
        }
        if file.removedLines > 0 {
          Text("-\(file.removedLines)")
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.red)
        }
      }
      .padding(.horizontal, 7)
      .frame(height: 28)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: .rect(cornerRadius: 5))
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }

  private var iconName: String {
    switch file.status {
    case .added: "plus.square"
    case .deleted: "minus.square"
    case .renamed: "arrow.triangle.2.circlepath"
    case .copied: "doc.on.doc"
    case .binary: "doc.badge.gearshape"
    case .modified: "doc.text"
    }
  }

  private var iconColor: Color {
    switch file.status {
    case .added: .green
    case .deleted: .red
    case .renamed, .copied: .orange
    case .binary: .secondary
    case .modified: .accentColor
    }
  }
}

private struct GitDiffContentView: View {
  let file: GitDiffFile?

  var body: some View {
    Group {
      if let file {
        ScrollView([.vertical, .horizontal]) {
          LazyVStack(alignment: .leading, spacing: 0) {
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
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        Spacer()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.horizontal, 10)
      .frame(minWidth: 720, maxWidth: .infinity, minHeight: 20, alignment: .leading)
      .textSelection(.enabled)
  }
}

private struct GitDiffHunkHeaderLine: View {
  let text: String

  var body: some View {
    Text(text)
      .font(diffFont.weight(.semibold))
      .foregroundStyle(Color(red: 0.62, green: 0.72, blue: 1.0))
      .lineLimit(1)
      .padding(.horizontal, 10)
      .frame(minWidth: 720, maxWidth: .infinity, minHeight: 22, alignment: .leading)
      .background(Color(red: 0.16, green: 0.18, blue: 0.28).opacity(0.55))
      .textSelection(.enabled)
  }
}

private struct GitDiffCodeLine: View {
  let line: GitDiffLine

  var body: some View {
    HStack(spacing: 0) {
      Text(oldNumber)
        .frame(width: 44, alignment: .trailing)
        .foregroundStyle(.secondary.opacity(0.7))
      Text(newNumber)
        .frame(width: 44, alignment: .trailing)
        .foregroundStyle(.secondary.opacity(0.7))
      Text(prefix)
        .frame(width: 20, alignment: .center)
        .foregroundStyle(prefixColor)
      Text(line.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(textColor)
    }
    .font(diffFont)
    .lineLimit(1)
    .padding(.horizontal, 10)
    .frame(minWidth: 720, maxWidth: .infinity, minHeight: 20, alignment: .leading)
    .background(backgroundColor)
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
    case .addition: .green
    case .deletion: .red
    case .context, .note: .secondary
    }
  }

  private var textColor: Color {
    switch line.kind {
    case .addition: Color(red: 0.78, green: 0.98, blue: 0.82)
    case .deletion: Color(red: 1.0, green: 0.76, blue: 0.76)
    case .context: .primary
    case .note: .secondary
    }
  }

  private var backgroundColor: Color {
    switch line.kind {
    case .addition: Color(red: 0.02, green: 0.26, blue: 0.13).opacity(0.62)
    case .deletion: Color(red: 0.35, green: 0.08, blue: 0.09).opacity(0.72)
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
    case .addition: .green
    case .deletion: .red
    }
  }

  private var backgroundColor: Color {
    switch kind {
    case .addition: Color.green.opacity(0.14)
    case .deletion: Color.red.opacity(0.14)
    }
  }
}

private let diffFont = Font.system(size: 11, design: .monospaced)
