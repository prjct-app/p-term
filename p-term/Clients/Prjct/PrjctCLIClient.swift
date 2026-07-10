import ComposableArchitecture
import Foundation
import PTermSettingsShared

nonisolated struct PrjctConfig: Equatable, Sendable {
  let projectID: String?
  let persona: String?

  nonisolated static func parse(data: Data) -> Self {
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return Self(projectID: nil, persona: nil)
    }
    let persona: String?
    if let raw = object["persona"] as? String {
      persona = raw
    } else if let raw = object["persona"] as? [String: Any] {
      let role = raw["role"] as? String
      let packs = (raw["packs"] as? [String])?.joined(separator: ", ")
      let parts = [role, packs]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      persona = parts.isEmpty ? nil : parts.joined(separator: " · ")
    } else {
      persona = nil
    }
    return Self(projectID: object["projectId"] as? String, persona: persona)
  }
}

nonisolated struct PrjctProjectStat: Equatable, Sendable, Identifiable {
  var id: String { label }
  let label: String
  let value: String
}

nonisolated struct PrjctDashboardMetric: Equatable, Sendable, Identifiable {
  var id: String { "\(label)-\(value)" }
  let label: String
  let value: String
  let detail: String?
}

nonisolated struct PrjctDashboardSection: Equatable, Sendable, Identifiable {
  var id: String { title }
  let title: String
  let metrics: [PrjctDashboardMetric]
}

nonisolated struct PrjctWorkflowRule: Equatable, Sendable, Identifiable {
  let id: String
  let title: String
  let command: String
  let stage: String?
}

/// Where a command's output should land. `.panel` commands are read-only
/// reports (`--md` snapshots) that stream their output into the prjct panel
/// itself; `.terminal` commands (interactive prompts, mutating workflows)
/// keep injecting into the live terminal surface, unchanged.
nonisolated enum PrjctCommandExecution: Equatable, Sendable {
  case panel
  case terminal
}

nonisolated struct PrjctTerminalCommand: Equatable, Sendable, Identifiable {
  let id: String
  let title: String
  let input: String
  let submit: Bool
  let systemImage: String
  let detail: String?
  let execution: PrjctCommandExecution

  init(
    id: String,
    title: String,
    input: String,
    submit: Bool = true,
    systemImage: String = "terminal",
    detail: String? = nil,
    execution: PrjctCommandExecution = .terminal
  ) {
    self.id = id
    self.title = title
    self.input = input
    self.submit = submit
    self.systemImage = systemImage
    self.detail = detail
    self.execution = execution
  }
}

nonisolated struct PrjctProjectSnapshot: Equatable, Sendable {
  let projectDirectory: URL?
  let config: PrjctConfig?
  let headline: String
  let statusStats: [PrjctProjectStat]
  let sections: [PrjctDashboardSection]
  let actions: [PrjctTerminalCommand]
  let workflows: [PrjctTerminalCommand]
  let workflowRules: [PrjctWorkflowRule]
  let reviewRisk: String?
  let delivery: String?
  let refreshedAt: Date?

  var isEnabled: Bool { projectDirectory != nil && config != nil }

  nonisolated static let notConfigured = Self(
    projectDirectory: nil,
    config: nil,
    headline: "No prjct project",
    statusStats: [],
    sections: [],
    actions: [],
    workflows: [],
    workflowRules: [],
    reviewRisk: nil,
    delivery: nil,
    refreshedAt: nil
  )
}

nonisolated enum PrjctProjectDetector {
  nonisolated static func projectDirectory(from candidates: [URL]) -> URL? {
    for candidate in candidates.map(\.standardizedFileURL)
    where FileManager.default.fileExists(atPath: configURL(in: candidate).path(percentEncoded: false))
    {
      return candidate
    }
    return nil
  }

  nonisolated static func configURL(in directory: URL) -> URL {
    directory
      .appending(path: ".prjct", directoryHint: .isDirectory)
      .appending(path: "prjct.config.json", directoryHint: .notDirectory)
  }
}

nonisolated struct PrjctCLIClient: Sendable {
  var inspect: @Sendable (_ candidateDirectories: [URL]) async -> PrjctProjectSnapshot
  /// Streams a `.panel`-executed command's stdout/stderr lines plus its final
  /// exit code, with an explicit terminate handle so the panel can cancel a
  /// run in flight.
  var runProcess: @Sendable (_ arguments: [String], _ directory: URL) -> StreamingShellProcess

  init(
    inspect: @escaping @Sendable (_ candidateDirectories: [URL]) async -> PrjctProjectSnapshot,
    runProcess: @escaping @Sendable (_ arguments: [String], _ directory: URL) -> StreamingShellProcess
  ) {
    self.inspect = inspect
    self.runProcess = runProcess
  }
}

extension PrjctCLIClient: DependencyKey {
  static let liveValue = PrjctCLIClient(inspect: { candidateDirectories in
    guard let projectDirectory = PrjctProjectDetector.projectDirectory(from: candidateDirectories) else {
      return .notConfigured
    }

    let configURL = PrjctProjectDetector.configURL(in: projectDirectory)
    let config = (try? Data(contentsOf: configURL)).map(PrjctConfig.parse(data:))

    async let status = runReadOnly(["prjct", "status", "--md"], in: projectDirectory)
    async let value = runReadOnly(["prjct", "insights", "--md"], in: projectDirectory)
    async let quality = runReadOnly(["prjct", "insights", "quality", "--md"], in: projectDirectory)
    async let reliability = runReadOnly(["prjct", "insights", "reliability", "--md"], in: projectDirectory)
    async let cost = runReadOnly(["prjct", "insights", "cost", "--md"], in: projectDirectory)
    async let performance = runReadOnly(["prjct", "performance", "7", "--md"], in: projectDirectory)
    async let reviewRisk = runReadOnly(["prjct", "review-risk"], in: projectDirectory)
    async let workflows = runReadOnly(["prjct", "workflow", "list", "--md"], in: projectDirectory)
    async let workflowRules = runReadOnly(["prjct", "workflow", "--md"], in: projectDirectory)
    async let commands = runReadOnly(["prjct", "help", "commands"], in: projectDirectory)

    let outputs = await (
      status,
      value,
      quality,
      reliability,
      cost,
      performance,
      reviewRisk,
      workflows,
      workflowRules,
      commands
    )

    let workflowCommands = PrjctCLIParser.parseWorkflowCommands(outputs.7)
    return PrjctProjectSnapshot(
      projectDirectory: projectDirectory,
      config: config,
      headline: PrjctCLIParser.headline(status: outputs.0, value: outputs.1),
      statusStats: PrjctCLIParser.parseStatus(outputs.0),
      sections: PrjctCLIParser.dashboardSections(
        .init(
          value: outputs.1,
          quality: outputs.2,
          reliability: outputs.3,
          cost: outputs.4,
          performance: outputs.5,
          reviewRisk: outputs.6
        )
      ),
      actions: PrjctCLIParser.primaryCommands(fromHelp: outputs.9, workflows: workflowCommands),
      workflows: workflowCommands,
      workflowRules: PrjctCLIParser.parseWorkflowRules(outputs.8),
      reviewRisk: PrjctCLIParser.reviewRiskSummary(outputs.6).risk,
      delivery: PrjctCLIParser.reviewRiskSummary(outputs.6).delivery,
      refreshedAt: Date()
    )
  },
    runProcess: { arguments, directory in
      @Dependency(\.shellClient) var shellClient
      return shellClient.runLoginProcess(
        URL(fileURLWithPath: "/usr/bin/env"), arguments, directory, log: false)
    }
  )

  static let testValue = PrjctCLIClient(
    inspect: { _ in .notConfigured },
    runProcess: { _, _ in StreamingShellProcess(events: AsyncThrowingStream { $0.finish() }, terminate: {}) }
  )

  private static func runReadOnly(_ arguments: [String], in projectDirectory: URL) async -> String {
    @Dependency(\.shellClient) var shellClient
    do {
      let output = try await shellClient.runLogin(
        URL(fileURLWithPath: "/usr/bin/env"),
        arguments,
        projectDirectory,
        log: false
      )
      return output.stdout
    } catch {
      return ""
    }
  }
}

extension DependencyValues {
  var prjctCLIClient: PrjctCLIClient {
    get { self[PrjctCLIClient.self] }
    set { self[PrjctCLIClient.self] = newValue }
  }
}

nonisolated enum PrjctCLIParser {
  nonisolated static func headline(status: String, value: String) -> String {
    if let score = score(in: value, named: "Value score") {
      return "Value \(score)"
    }
    let stats = parseStatus(status)
    if let task = stats.first(where: { $0.label == "Status" })?.value {
      return "Status \(task)"
    }
    return "Project dashboard"
  }

  nonisolated static func parseStatus(_ output: String) -> [PrjctProjectStat] {
    output
      .split(whereSeparator: \.isNewline)
      .flatMap { line in
        line.split(separator: "|").compactMap { chunk -> PrjctProjectStat? in
          let text = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
          guard let separator = text.firstIndex(of: ":") else { return nil }
          let label = text[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
          let value = text[text.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
          guard !label.isEmpty, !value.isEmpty else { return nil }
          return PrjctProjectStat(label: label, value: value)
        }
      }
  }

  /// Bundles the six insight CLI outputs so `dashboardSections` stays under the
  /// function-parameter-count lint limit without losing named fields at call sites.
  nonisolated struct DashboardSectionInputs: Sendable {
    var value: String
    var quality: String
    var reliability: String
    var cost: String
    var performance: String
    var reviewRisk: String
  }

  nonisolated static func dashboardSections(_ inputs: DashboardSectionInputs) -> [PrjctDashboardSection] {
    [
      PrjctDashboardSection(
        title: "Value",
        metrics: compactMetrics([
          metric("Score", score(in: inputs.value, named: "Value score")),
          tableMetric(inputs.value, "Completed tasks"),
          tableMetric(inputs.value, "Shipped features"),
          tableMetric(inputs.value, "Sync runs"),
          tableMetric(inputs.value, "Tokens saved by sync metrics"),
        ])
      ),
      PrjctDashboardSection(
        title: "Performance",
        metrics: performanceMetrics(inputs.performance)
      ),
      PrjctDashboardSection(
        title: "Quality",
        metrics: compactMetrics([
          metric("Score", score(in: inputs.quality, named: "Quality score")),
          firstIssueMetric(inputs.quality),
        ])
      ),
      PrjctDashboardSection(
        title: "Reliability",
        metrics: compactMetrics([
          metric("Score", score(in: inputs.reliability, named: "Reliability score")),
          tableMetric(inputs.reliability, "Token attribution"),
          tableMetric(inputs.reliability, "Context reuse proof"),
          tableMetric(inputs.reliability, "Average startup"),
        ])
      ),
      PrjctDashboardSection(
        title: "Cost",
        metrics: compactMetrics([
          tableMetric(inputs.cost, "Work cycles"),
          tableMetric(inputs.cost, "Token coverage"),
          tableMetric(inputs.cost, "Total tokens"),
          tableMetric(inputs.cost, "Agent sessions"),
        ])
      ),
      PrjctDashboardSection(
        title: "Review",
        metrics: compactMetrics([
          metric("Risk", reviewRiskSummary(inputs.reviewRisk).risk),
          metric("Delivery", reviewRiskSummary(inputs.reviewRisk).delivery),
        ])
      ),
    ]
    .filter { !$0.metrics.isEmpty }
  }

  nonisolated static func primaryCommands(
    fromHelp output: String,
    workflows: [PrjctTerminalCommand]
  ) -> [PrjctTerminalCommand] {
    let available = Set(parseCommandNames(output))
    let commands = [
      terminalCommand(
        "sync", available: available, title: "Sync", input: "prjct sync --md", icon: "arrow.triangle.2.circlepath"),
      terminalCommand(
        "work", available: available, title: "Work", input: "prjct work ", submit: false, icon: "text.badge.plus"),
      terminalCommand("ship", available: available, title: "Ship", input: "prjct ship --md", icon: "paperplane"),
      terminalCommand(
        "performance", available: available, title: "Performance", input: "prjct performance 7 --md",
        icon: "chart.xyaxis.line", execution: .panel),
      terminalCommand(
        "insights", available: available, title: "Insights", input: "prjct insights --md", icon: "sparkles",
        execution: .panel),
      terminalCommand(
        "review-risk", available: available, title: "Review Risk", input: "prjct review-risk",
        icon: "exclamationmark.triangle", execution: .panel),
      terminalCommand(
        "workflow", available: available, title: "Workflow", input: "prjct workflow ", submit: false,
        icon: "checklist"),
    ]
    .compactMap(\.self)

    return commands + Array(workflows.prefix(4))
  }

  nonisolated static func parseWorkflowCommands(_ output: String) -> [PrjctTerminalCommand] {
    output
      .split(whereSeparator: \.isNewline)
      .compactMap { rawLine -> PrjctTerminalCommand? in
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("- **"),
          let endName = line.range(of: "**", range: line.index(line.startIndex, offsetBy: 4)..<line.endIndex)
        else {
          return nil
        }
        let name = String(line[line.index(line.startIndex, offsetBy: 4)..<endName.lowerBound])
        let description = line[endName.upperBound...]
          .replacingOccurrences(of: "—", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return PrjctTerminalCommand(
          id: "workflow-\(name)",
          title: name,
          input: "prjct workflow \(shellQuote(name)) --md",
          systemImage: "checkmark.seal",
          detail: description.isEmpty ? nil : description
        )
      }
  }

  nonisolated static func parseWorkflowRules(_ output: String) -> [PrjctWorkflowRule] {
    output
      .split(whereSeparator: \.isNewline)
      .compactMap { rawLine -> PrjctWorkflowRule? in
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("|"), line.contains("# #") else { return nil }
        line.removeFirst()
        if line.last == "|" { line.removeLast() }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("# #") else { return nil }
        let remainder = line.dropFirst(3)
        let number = remainder.prefix { $0.isNumber }
        let command = remainder.dropFirst(number.count)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty, !command.isEmpty else { return nil }
        return PrjctWorkflowRule(
          id: "rule-\(number)-\(command.hashValue)",
          title: "Gate #\(number)",
          command: command,
          stage: "ship"
        )
      }
  }

  nonisolated static func reviewRiskSummary(_ output: String) -> (risk: String?, delivery: String?) {
    var risk: String?
    var delivery: String?
    for line in output.split(whereSeparator: \.isNewline) {
      let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.hasPrefix("Review risk:") {
        risk = text.replacingOccurrences(of: "Review risk:", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
      } else if text.hasPrefix("Delivery:") {
        delivery = text.replacingOccurrences(of: "Delivery:", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return (risk, delivery)
  }

  private nonisolated static func parseCommandNames(_ output: String) -> [String] {
    output
      .split(whereSeparator: \.isNewline)
      .compactMap { line -> String? in
        let text = line.trimmingCharacters(in: .whitespaces)
        let prefixes = ["prjct ", "p. "]
        guard let prefix = prefixes.first(where: { text.hasPrefix($0) }) else { return nil }
        let remainder = text.dropFirst(prefix.count)
        let name = remainder.prefix { !$0.isWhitespace }
        return name.isEmpty ? nil : String(name)
      }
  }

  private nonisolated static func terminalCommand(
    _ name: String,
    available: Set<String>,
    title: String,
    input: String,
    submit: Bool = true,
    icon: String,
    execution: PrjctCommandExecution = .terminal
  ) -> PrjctTerminalCommand? {
    guard available.contains(name) else { return nil }
    return PrjctTerminalCommand(
      id: "command-\(name)",
      title: title,
      input: input,
      submit: submit,
      systemImage: icon,
      execution: execution
    )
  }

  private nonisolated static func performanceMetrics(_ output: String) -> [PrjctDashboardMetric] {
    let rows = markdownTableRows(output).filter { $0.keys["Work cycle"] != nil }
    let completed = rows.filter { $0.value(for: "Outcome") == "completed" }.count
    let inProgress = rows.filter { $0.value(for: "Outcome") == "in_progress" }.count
    let tokens = rows.compactMap { Int(($0.value(for: "Tokens") ?? "").replacingOccurrences(of: ",", with: "")) }
      .reduce(0, +)
    let subagents = rows.compactMap { Int($0.value(for: "Subagents") ?? "") }.reduce(0, +)
    return compactMetrics([
      metric("Work cycles", rows.isEmpty ? nil : "\(rows.count)"),
      metric("Completed", rows.isEmpty ? nil : "\(completed)"),
      metric("In progress", inProgress > 0 ? "\(inProgress)" : nil),
      metric("Measured tokens", tokens > 0 ? formattedNumber(tokens) : nil),
      metric("Subagents", subagents > 0 ? "\(subagents)" : "0"),
    ])
  }

  private nonisolated static func score(in output: String, named name: String) -> String? {
    for line in output.split(whereSeparator: \.isNewline) {
      let cleaned = line.replacingOccurrences(of: "**", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard cleaned.lowercased().hasPrefix(name.lowercased()),
        let separator = cleaned.firstIndex(of: ":")
      else { continue }
      let value = cleaned[cleaned.index(after: separator)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : String(value)
    }
    return nil
  }

  private nonisolated static func tableMetric(_ output: String, _ label: String) -> PrjctDashboardMetric? {
    guard let value = markdownTableRows(output).compactMap({ $0.value(for: label) }).first else {
      return nil
    }
    return metric(label, value)
  }

  private nonisolated static func firstIssueMetric(_ output: String) -> PrjctDashboardMetric? {
    if output.contains("No obvious memory quality issues found") {
      return metric("Issues", "None")
    }
    return nil
  }

  private nonisolated static func compactMetrics(_ metrics: [PrjctDashboardMetric?]) -> [PrjctDashboardMetric] {
    metrics.compactMap(\.self)
  }

  private nonisolated static func metric(
    _ label: String,
    _ value: String?,
    detail: String? = nil
  ) -> PrjctDashboardMetric? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return PrjctDashboardMetric(label: label, value: value, detail: detail)
  }

  private nonisolated static func markdownTableRows(_ output: String) -> [MarkdownTableRow] {
    var headers: [String] = []
    var rows: [MarkdownTableRow] = []
    for rawLine in output.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard line.hasPrefix("|"), line.hasSuffix("|") else { continue }
      let cells = line.dropFirst().dropLast()
        .split(separator: "|", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      guard cells.count >= 2 else { continue }
      if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) {
        continue
      }
      if headers.isEmpty {
        headers = cells
        continue
      }
      rows.append(MarkdownTableRow(headers: headers, cells: cells))
    }
    return rows
  }

  private nonisolated static func formattedNumber(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  private nonisolated static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

private nonisolated struct MarkdownTableRow {
  let headers: [String]
  let cells: [String]
  let keys: [String: String]

  init(headers: [String], cells: [String]) {
    self.headers = headers
    self.cells = cells
    var keys: [String: String] = [:]
    for (index, header) in headers.enumerated() where index < cells.count {
      keys[header] = cells[index]
    }
    self.keys = keys
  }

  func value(for label: String) -> String? {
    if let direct = keys[label] { return direct }
    if cells.count >= 2, cells[0] == label {
      return cells[1]
    }
    return nil
  }
}
