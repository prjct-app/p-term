import Foundation
import Testing

@testable import p_term

struct PrjctCLIClientTests {
  private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "pterm-prjct-panel-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func detectorFindsDirectoryWithPrjctConfig() throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let prjctDirectory = root.appending(path: ".prjct", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: prjctDirectory, withIntermediateDirectories: true)
    try Data(#"{"projectId":"abc","persona":"code"}"#.utf8)
      .write(to: prjctDirectory.appending(path: "prjct.config.json"))

    let detected = PrjctProjectDetector.projectDirectory(from: [root])

    #expect(detected == root.standardizedFileURL)
  }

  @Test func detectorSkipsDirectoriesWithoutPrjctConfig() throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let detected = PrjctProjectDetector.projectDirectory(from: [root])

    #expect(detected == nil)
  }

  @Test func parsesStatusStats() {
    let output = """
      Task: 624ae58f-a648-4702-9732-489b9d518c63  |  Type: feature  |  Status: active
      Harness: H2 feature/medium
      """

    let stats = PrjctCLIParser.parseStatus(output)

    #expect(stats.map(\.label) == ["Task", "Type", "Status", "Harness"])
    #expect(
      stats.map(\.value) == [
        "624ae58f-a648-4702-9732-489b9d518c63",
        "feature",
        "active",
        "H2 feature/medium",
      ])
  }

  @Test func parsesWorkflowRulesWithPipeCommands() {
    let output = """
      ### Workflow Rules
      1 rule

      ```
      +---------------------------------------------------------------+
      | GATES (must pass)                                             |
      |   # #1 git branch --show-current | grep -vE "^(main|master)$" |
      +---------------------------------------------------------------+
      ```
      """

    let workflows = PrjctCLIParser.parseWorkflowRules(output)

    #expect(workflows.count == 1)
    #expect(workflows[0].title == "Gate #1")
    #expect(workflows[0].command == #"git branch --show-current | grep -vE "^(main|master)$""#)
    #expect(workflows[0].stage == "ship")
  }

  @Test func parsesWorkflowCommandsFromMarkdownList() {
    let output = """
      ### Built-in Workflows
      - **ship** — Ship feature with version bump and PR
      - **sync** — Analyze project and regenerate context
      """

    let workflows = PrjctCLIParser.parseWorkflowCommands(output)

    #expect(workflows.map(\.title) == ["ship", "sync"])
    #expect(workflows[0].input == "prjct workflow 'ship' --md")
    #expect(workflows[0].detail == "Ship feature with version bump and PR")
  }

  @Test func buildsDashboardSectionsFromAggregatedMetrics() {
    let value = """
      # prjct Value

      **Value score:** 81/100

      | Area | Signal |
      |---|---:|
      | Completed tasks | 3 / 4 |
      | Shipped features | 2 |
      | Sync runs | 5 |
      | Tokens saved by sync metrics | 196,650 |
      """
    let reliability = """
      **Reliability score:** 77/100

      | Signal | Coverage |
      |---|---:|
      | Token attribution | 75% |
      | Context reuse proof | 3% |
      | Average startup | 3.2s |
      """
    let quality = """
      **Quality score:** 100/100

      - No obvious memory quality issues found.
      """
    let cost = """
      | Metric | Value |
      |---|---:|
      | Work cycles | 4 |
      | Token coverage | 75% |
      | Total tokens | 5,092,074 |
      | Agent sessions | 4 |
      """
    let performance = """
      | Work cycle | Outcome | Time | Tokens | Subagents |
      |---|---|---:|---:|---:|
      | A | completed | 10 | 1,000 | 2 |
      | B | in_progress | unknown | 500 | 0 |
      """
    let reviewRisk = """
      Review risk: NORMAL — 4 files, 66 LOC
      Delivery: single — Cohesive
      """

    let sections = PrjctCLIParser.dashboardSections(
      .init(
        value: value,
        quality: quality,
        reliability: reliability,
        cost: cost,
        performance: performance,
        reviewRisk: reviewRisk
      )
    )

    #expect(sections.first { $0.title == "Value" }?.metrics.first?.value == "81/100")
    #expect(sections.first { $0.title == "Performance" }?.metrics.map(\.value).contains("2") == true)
    #expect(sections.first { $0.title == "Review" }?.metrics.first?.value == "NORMAL — 4 files, 66 LOC")
  }
}
