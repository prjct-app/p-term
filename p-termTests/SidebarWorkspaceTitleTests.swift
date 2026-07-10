import Foundation
import Testing

@testable import p_term

@Suite("SidebarWorkspaceTitle")
struct SidebarWorkspaceTitleTests {
  @Test func customTitleAlwaysWins() {
    let title = SidebarWorkspaceTitle.resolve(
      .init(
        customTitle: "  My workspace  ",
        repositoryName: "prjct-code",
        isFolder: false,
        folderOrName: "feat/ux-liquid-glass",
        workingDirectoryName: "feat-ux-liquid-glass",
        isNestedUnderProject: false
      )
    )
    #expect(title == "My workspace")
  }

  @Test func flatListUsesRepositoryNameNeverBranch() {
    let title = SidebarWorkspaceTitle.resolve(
      .init(
        customTitle: nil,
        repositoryName: "prjct-code",
        isFolder: false,
        folderOrName: "feat/ux-liquid-glass",
        workingDirectoryName: "feat-ux-liquid-glass",
        isNestedUnderProject: false
      )
    )
    #expect(title == "prjct-code")
    #expect(!title.contains("feat/"))
  }

  @Test func nestedUnderProjectUsesDirectoryNotBranchPath() {
    let title = SidebarWorkspaceTitle.resolve(
      .init(
        customTitle: nil,
        repositoryName: "prjct-code",
        isFolder: false,
        folderOrName: "feat/ux-liquid-glass",
        workingDirectoryName: "feat-ux-liquid-glass",
        isNestedUnderProject: true
      )
    )
    #expect(title == "feat-ux-liquid-glass")
    #expect(title != "feat/ux-liquid-glass")
  }

  @Test func nestedMainWorktreeNeverUsesLiteralWorkspaceWord() {
    let title = SidebarWorkspaceTitle.resolve(
      .init(
        customTitle: nil,
        repositoryName: "prjct-cli",
        isFolder: false,
        folderOrName: "main",
        workingDirectoryName: "prjct-cli",
        isNestedUnderProject: true
      )
    )
    #expect(title != "Workspace")
    #expect(title == "prjct-cli" || title == "main")
  }

  @Test func nestedRejectsBranchSlashPathAsTitle() {
    let title = SidebarWorkspaceTitle.resolve(
      .init(
        customTitle: nil,
        repositoryName: "prjct-code",
        isFolder: false,
        folderOrName: "feat/ux-liquid-glass",
        workingDirectoryName: "",
        isNestedUnderProject: true
      )
    )
    #expect(!title.contains("/"))
    #expect(title != "Workspace")
    #expect(title == "prjct-code")
  }

  @Test func neverEmitsLiteralWorkspaceAsTitle() {
    let cases: [SidebarWorkspaceTitle.Inputs] = [
      .init(
        customTitle: nil, repositoryName: "baymax", isFolder: false,
        folderOrName: "main", workingDirectoryName: "baymax", isNestedUnderProject: false),
      .init(
        customTitle: nil, repositoryName: "baymax", isFolder: false,
        folderOrName: "main", workingDirectoryName: "baymax", isNestedUnderProject: true),
      .init(
        customTitle: nil, repositoryName: nil, isFolder: false,
        folderOrName: "", workingDirectoryName: "", isNestedUnderProject: false),
    ]
    for inputs in cases {
      #expect(SidebarWorkspaceTitle.resolve(inputs) != "Workspace")
    }
  }

  @Test func folderUsesFolderNameWhenNoRepo() {
    let title = SidebarWorkspaceTitle.resolve(
      .init(
        customTitle: nil,
        repositoryName: nil,
        isFolder: true,
        folderOrName: "Documents",
        workingDirectoryName: "Documents",
        isNestedUnderProject: false
      )
    )
    #expect(title == "Documents")
  }

  @Test func emptyInputsFallBackToUntitledNotWorkspaceWord() {
    let title = SidebarWorkspaceTitle.resolve(
      .init(
        customTitle: "   ",
        repositoryName: nil,
        isFolder: false,
        folderOrName: "",
        workingDirectoryName: "",
        isNestedUnderProject: false
      )
    )
    #expect(title == "Untitled")
    #expect(title != "Workspace")
  }

  @Test func whitespaceOnlyCustomFallsThroughToRepo() {
    let title = SidebarWorkspaceTitle.resolve(
      .init(
        customTitle: "\n\t",
        repositoryName: "baymax",
        isFolder: false,
        folderOrName: "main",
        workingDirectoryName: "baymax",
        isNestedUnderProject: false
      )
    )
    #expect(title == "baymax")
  }
}

@Suite("SidebarAccessibility New Terminal CTA")
struct SidebarNewTerminalAccessibilityTests {
  @Test func newTerminalCTALabelIsStable() {
    #expect(SidebarAccessibility.newTerminalCTALabel() == "New Terminal")
  }
}
