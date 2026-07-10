import ComposableArchitecture
import Foundation
import PTermSettingsShared

/// One in-panel command execution: streamed output tail + terminal status.
/// Kept in-memory only (capped history) — this is a live-run log, not a
/// persisted audit trail.
struct PrjctCommandRun: Equatable, Identifiable, Sendable {
  enum Status: Equatable, Sendable {
    case running
    case succeeded
    case failed
    case cancelled
  }

  let id: UUID
  let command: PrjctTerminalCommand
  let startedAt: Date
  var status: Status
  var outputTail: [String]
  var exitCode: Int32?

  /// Ring buffer cap: enough context to read a `--md` report without the
  /// panel holding unbounded output for a runaway command.
  static let outputTailLimit = 500

  mutating func appendOutput(_ line: String) {
    outputTail.append(line)
    if outputTail.count > Self.outputTailLimit {
      outputTail.removeFirst(outputTail.count - Self.outputTailLimit)
    }
  }
}

@Reducer
struct PrjctPanelFeature {
  @ObservableState
  struct State: Equatable {
    var context = PrjctPanelContext()
    var snapshot: PrjctProjectSnapshot = .notConfigured
    var isVisible = false
    var isLoading = false
    var errorMessage: String?
    /// Most recent run first. Capped so a long session doesn't grow unbounded.
    var runs: [PrjctCommandRun] = []

    var isEnabled: Bool { snapshot.isEnabled }

    static let runHistoryLimit = 20

    /// Mutates the run matching `runID` in place. No-ops if the run isn't
    /// found — a normal race when a run finishes/errors around the same time
    /// as another event for it.
    mutating func updateRun(_ runID: UUID, _ mutate: (inout PrjctCommandRun) -> Void) {
      guard let index = runs.firstIndex(where: { $0.id == runID }) else { return }
      mutate(&runs[index])
    }
  }

  enum Action: Equatable {
    case contextChanged(PrjctPanelContext)
    case toggleVisibility
    case setVisibility(Bool)
    case refresh
    case refreshed(PrjctProjectSnapshot)
    case runCommand(PrjctTerminalCommand)
    case commandOutputLine(runID: UUID, text: String)
    case commandFinished(runID: UUID, exitCode: Int32)
    case commandFailed(runID: UUID)
    case cancelRun(runID: UUID)
  }

  @Dependency(PrjctCLIClient.self) private var prjct
  @Dependency(\.date.now) private var now

  private nonisolated enum CancelID { case refresh }
  private nonisolated struct RunCancelID: Hashable, Sendable { let runID: UUID }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .contextChanged(let context):
        let previousDirectories = state.context.candidateDirectories
        state.context = context
        state.errorMessage = nil
        if context.isRemote || context.candidateDirectories.isEmpty {
          state.snapshot = .notConfigured
          state.isVisible = false
          state.isLoading = false
          return .cancel(id: CancelID.refresh)
        }
        guard previousDirectories != context.candidateDirectories || !state.snapshot.isEnabled else {
          return .none
        }
        return .send(.refresh)

      case .toggleVisibility:
        guard state.snapshot.isEnabled else { return .none }
        state.isVisible.toggle()
        return state.isVisible ? .send(.refresh) : .none

      case .setVisibility(let isVisible):
        state.isVisible = isVisible && state.snapshot.isEnabled
        return state.isVisible ? .send(.refresh) : .none

      case .refresh:
        guard !state.context.isRemote else {
          state.snapshot = .notConfigured
          state.isVisible = false
          return .none
        }
        let candidates = state.context.candidateDirectories
        state.isLoading = true
        state.errorMessage = nil
        return .run { send in
          await send(.refreshed(prjct.inspect(candidates)))
        }
        .cancellable(id: CancelID.refresh, cancelInFlight: true)

      case .refreshed(let snapshot):
        state.isLoading = false
        state.snapshot = snapshot
        if !snapshot.isEnabled {
          state.isVisible = false
        }
        return .none

      case .runCommand(let command):
        guard let directory = state.snapshot.projectDirectory else { return .none }
        let runID = UUID()
        state.runs.insert(
          PrjctCommandRun(id: runID, command: command, startedAt: now, status: .running, outputTail: []),
          at: 0
        )
        if state.runs.count > State.runHistoryLimit {
          state.runs.removeLast(state.runs.count - State.runHistoryLimit)
        }
        // These commands are the fixed, unquoted `--md` reports classified
        // `.panel` in `PrjctCLIParser.primaryCommands` — plain whitespace
        // splitting is safe for them. Workflow commands (which can carry a
        // shell-quoted, space-containing name) stay `.terminal` and never
        // reach this path.
        let arguments = command.input.split(separator: " ").map(String.init)
        let runProcess = prjct.runProcess
        return .run { send in
          let process = runProcess(arguments, directory)
          await withTaskCancellationHandler(
            operation: {
              await Self.consumeRunEvents(process: process, runID: runID, send: send)
            },
            onCancel: {
              process.terminate()
            }
          )
        }
        .cancellable(id: RunCancelID(runID: runID))

      case .commandOutputLine(let runID, let text):
        state.updateRun(runID) { $0.appendOutput(text) }
        return .none

      case .commandFinished(let runID, let exitCode):
        state.updateRun(runID) {
          $0.status = exitCode == 0 ? .succeeded : .failed
          $0.exitCode = exitCode
        }
        return .none

      case .commandFailed(let runID):
        state.updateRun(runID) { $0.status = .failed }
        return .none

      case .cancelRun(let runID):
        guard let index = state.runs.firstIndex(where: { $0.id == runID }),
          state.runs[index].status == .running
        else {
          return .none
        }
        state.runs[index].status = .cancelled
        return .cancel(id: RunCancelID(runID: runID))
      }
    }
  }

  private static func consumeRunEvents(
    process: StreamingShellProcess, runID: UUID, send: Send<Action>
  ) async {
    do {
      for try await event in process.events {
        switch event {
        case .line(let line):
          await send(.commandOutputLine(runID: runID, text: line.text))
        case .finished(let output):
          await send(.commandFinished(runID: runID, exitCode: output.exitCode))
        }
      }
    } catch {
      await send(.commandFailed(runID: runID))
    }
  }
}

struct PrjctPanelContext: Equatable, Sendable {
  var worktreeID: Worktree.ID?
  var tabID: TerminalTabID?
  var surfaceID: UUID?
  var workingDirectory: URL?
  var repositoryRootURL: URL?
  var isRemote = false

  var candidateDirectories: [URL] {
    var directories: [URL] = []
    for url in [workingDirectory, repositoryRootURL].compactMap({ $0?.standardizedFileURL })
    where !directories.contains(url)
    {
      directories.append(url)
    }
    return directories
  }
}

extension PrjctPanelContext {
  init(worktree: Worktree, tabID: TerminalTabID? = nil, surfaceID: UUID? = nil) {
    self.init(
      worktreeID: worktree.id,
      tabID: tabID,
      surfaceID: surfaceID,
      workingDirectory: worktree.localWorkingDirectory,
      repositoryRootURL: worktree.host == nil ? worktree.repositoryRootURL : nil,
      isRemote: worktree.host != nil
    )
  }
}
