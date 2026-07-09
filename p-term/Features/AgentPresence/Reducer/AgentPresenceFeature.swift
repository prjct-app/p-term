import ComposableArchitecture
import Darwin
import Foundation
import PTermSettingsShared
import Sharing

@Reducer
struct AgentPresenceFeature {
  /// Activity state per (surface, agent). Set atomically by the wire events
  /// `busy` / `awaiting_input` / `idle`. The agent's Stop equivalent fires
  /// `idle`; `awaiting_input` is an explicit prompt the user must answer.
  enum Activity: String, Sendable, Equatable {
    case awaitingInput
    case busy
    case idle
  }

  /// One badge worth of state for a specific terminal surface.
  struct AgentInstance: Hashable, Sendable {
    let agent: SkillAgent
    let surfaceID: UUID
    let activity: Activity

    /// The avatar group flips contrast on awaiting-input instances.
    var awaitingInput: Bool { activity == .awaitingInput }
  }

  // `nonisolated` so `stageRestore` (off-main at launch) can use Hashable.
  nonisolated struct PresenceKey: Hashable, Sendable {
    let agent: SkillAgent
    let surfaceID: UUID
  }

  nonisolated struct PresenceRecord: Equatable, Sendable {
    var activity: Activity = .idle
    /// Local pids attributed to this record. Empty means the OSC presence was
    /// emitted without a local pid (SSH attach); `pids.isEmpty` is the
    /// discriminator for the pid-less lifecycle branches below. Every event
    /// arrives over OSC now, so there is no "socket-owned" record to defend
    /// against.
    var pids: Set<pid_t>
  }

  nonisolated struct RestoredRecord: Sendable {
    let alivePids: Set<pid_t>
    let activity: Activity
  }

  // `nonisolated` is load-bearing here. Without it the @Reducer macro
  // propagates main-actor isolation onto CancelID's Hashable witness, which
  // then can't satisfy the Sendable requirement in `.cancellable(id:)`.
  nonisolated enum CancelID: Hashable, Sendable { case livenessSweep }

  enum Action {
    case delegate(Delegate)
    case hookEventReceived(AgentHookEvent)
    case livenessSweepTick
    case livenessSweepResult(snapshot: [PresenceKey: Set<pid_t>], alive: [PresenceKey: Set<pid_t>])
    case start
    case stop
    case surfaceClosed(UUID)
    case surfacesClosed(Set<UUID>)
    /// Stage records for the off-main liveness pass. Apply lands as
    /// `restoreFromSnapshotChecked` so `kill(2)` never runs on the main actor.
    case restoreFromSnapshot(staged: [PresenceKey: StagedRestore])
    case restoreFromSnapshotChecked(records: [PresenceKey: RestoredRecord])

    enum Delegate: Equatable, Sendable {
      /// Surfaces whose presence record was added, removed, or had its activity flip.
      /// Parent fans out per-row `agentSnapshotChanged` via the `surfaceToItemID` reverse index.
      case surfacesChanged(Set<UUID>)
      /// An existing (surface, agent) record flipped activity. Only fires for
      /// records that already existed (fresh session starts don't count as a
      /// "transition" — there's no prior state to have moved on from). The
      /// parent decides which transitions are notification-worthy.
      case activityTransition(surfaceID: UUID, agent: SkillAgent, from: Activity, to: Activity)
    }
  }

  @ObservableState
  struct State: Equatable {
    /// Per-(surface, agent) record. Pids drive the liveness sweep and record
    /// disposal. Socket bridges carry a pid; the OSC-over-SSH transport seeds
    /// pid-less records that the sweep skips.
    var records: [PresenceKey: PresenceRecord] = [:]
    /// Per-surface agent presence. A surface can host multiple agents (rare,
    /// but possible if e.g. Claude spawns Codex). Order not guaranteed; sort before display.
    var bySurface: [UUID: Set<SkillAgent>] = [:]
  }

  /// Period between liveness sweeps. Cost scales with active sessions, not
  /// with the system process count. `nonisolated` so the Reduce closure can
  /// read it without crossing main-actor isolation.
  nonisolated static let livenessSweepInterval: Duration = .seconds(2)

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      @Dependency(\.continuousClock) var clock
      switch action {
      case .delegate:
        return .none

      case .hookEventReceived(let event):
        let (changed, transition) = Self.apply(event: event, into: &state)
        var effects = [Self.surfacesChangedEffect(changed)]
        if let transition {
          effects.append(
            .send(
              .delegate(
                .activityTransition(
                  surfaceID: transition.surfaceID,
                  agent: transition.agent,
                  from: transition.from,
                  to: transition.to
                )
              )
            )
          )
        }
        return .merge(effects)

      case .livenessSweepTick:
        // Run `kill(2)` off the main actor; the reducer body is shared with action-burst paths.
        let snapshot: [PresenceKey: Set<pid_t>] = state.records
          .compactMapValues { record in record.pids.isEmpty ? nil : record.pids }
        guard !snapshot.isEmpty else { return .none }
        return .run { send in
          let alive = Self.liveness(forSnapshot: snapshot)
          guard !alive.isEmpty else { return }
          await send(.livenessSweepResult(snapshot: snapshot, alive: alive))
        }

      case .livenessSweepResult(let snapshot, let alive):
        let changed = Self.applyLiveness(delta: alive, snapshot: snapshot, into: &state)
        return Self.surfacesChangedEffect(changed)

      case .start:
        return .run { send in
          for await _ in clock.timer(interval: Self.livenessSweepInterval) {
            await send(.livenessSweepTick)
          }
        }
        .cancellable(id: CancelID.livenessSweep, cancelInFlight: true)

      case .stop:
        return .cancel(id: CancelID.livenessSweep)

      case .surfaceClosed(let id):
        Self.drop(surfaces: [id], from: &state)
        return Self.surfacesChangedEffect([id])

      case .surfacesClosed(let ids):
        Self.drop(surfaces: ids, from: &state)
        return Self.surfacesChangedEffect(ids)

      case .restoreFromSnapshot(let staged):
        guard !staged.isEmpty else { return .none }
        return .run { send in
          let checked = staged.compactMapValues { stage -> RestoredRecord? in
            let alive = stage.pids.filter { Self.isAlive($0) }
            guard !alive.isEmpty else { return nil }
            return RestoredRecord(alivePids: alive, activity: stage.activity)
          }
          guard !checked.isEmpty else { return }
          await send(.restoreFromSnapshotChecked(records: checked))
        }

      case .restoreFromSnapshotChecked(let records):
        let changed = Self.applyRestore(records: records, into: &state)
        return Self.surfacesChangedEffect(changed)
      }
    }
  }

  private static func surfacesChangedEffect(_ surfaces: Set<UUID>) -> Effect<Action> {
    guard !surfaces.isEmpty else { return .none }
    return .send(.delegate(.surfacesChanged(surfaces)))
  }

  // MARK: - Mutators.

  /// One activity flip on an already-existing (surface, agent) record.
  private struct ActivityTransition {
    let surfaceID: UUID
    let agent: SkillAgent
    let from: Activity
    let to: Activity
  }

  /// Returns the surface IDs whose row-visible state changed, so the parent can fan
  /// out per-row `agentSnapshotChanged` deltas without inspecting `bySurface` itself,
  /// plus an activity transition if this event flipped an existing record's activity.
  private static func apply(
    event: AgentHookEvent, into state: inout State
  ) -> (surfaces: Set<UUID>, transition: ActivityTransition?) {
    guard let agent = SkillAgent(rawValue: event.agent) else { return ([], nil) }
    let key = PresenceKey(agent: agent, surfaceID: event.surfaceID)
    switch event.eventName {
    case .sessionStart:
      // A pid is the local-hook source (OSC presence carries `pid=$PPID` only on
      // the local host); a missing pid is the OSC-over-SSH source, which attributes
      // by the receiving surface and has no local pid to track.
      if let pid = event.pid {
        let isNewRecord = state.records[key] == nil
        var record = state.records[key] ?? PresenceRecord(pids: [])
        let inserted = record.pids.insert(pid).inserted
        state.records[key] = record
        if isNewRecord {
          insertPresence(agent: agent, surfaceID: event.surfaceID, in: &state)
        }
        return (inserted ? [event.surfaceID] : [], nil)
      }
      // Pid-less OSC seed: don't clobber a record that already carries a pid.
      guard state.records[key] == nil else { return ([], nil) }
      state.records[key] = PresenceRecord(pids: [])
      insertPresence(agent: agent, surfaceID: event.surfaceID, in: &state)
      return ([event.surfaceID], nil)
    case .sessionEnd:
      if let pid = event.pid {
        guard var record = state.records[key] else { return ([], nil) }
        let removed = record.pids.remove(pid) != nil
        if record.pids.isEmpty {
          state.records.removeValue(forKey: key)
          removePresence(agent: agent, surfaceID: event.surfaceID, in: &state)
        } else {
          state.records[key] = record
        }
        return (removed ? [event.surfaceID] : [], nil)
      }
      // Pid-less (OSC over SSH): only tear down a pid-less record; never one
      // that carries a tracked local pid the liveness sweep still owns.
      guard let record = state.records[key], record.pids.isEmpty else { return ([], nil) }
      state.records.removeValue(forKey: key)
      removePresence(agent: agent, surfaceID: event.surfaceID, in: &state)
      return ([event.surfaceID], nil)
    case .busy:
      return activityResult(.busy, agent: agent, event: event, key: key, into: &state)
    case .awaitingInput:
      return activityResult(.awaitingInput, agent: agent, event: event, key: key, into: &state)
    case .idle:
      return activityResult(.idle, agent: agent, event: event, key: key, into: &state)
    case .notification, .none:
      return ([], nil)
    }
  }

  private static func activityResult(
    _ activity: Activity, agent: SkillAgent, event: AgentHookEvent, key: PresenceKey, into state: inout State
  ) -> (surfaces: Set<UUID>, transition: ActivityTransition?) {
    let (changed, flip) = applyActivity(activity, event: event, key: key, into: &state)
    guard changed else { return ([], nil) }
    let transition = flip.map {
      ActivityTransition(surfaceID: event.surfaceID, agent: agent, from: $0.from, to: $0.to)
    }
    return ([event.surfaceID], transition)
  }

  /// Auto-seed only on the OSC path (pid == nil), and only when the activity
  /// would actually carry a badge: SSH attach can land on `busy` /
  /// `awaiting_input` with no prior `session_start`, but an `idle` arriving
  /// after the `session_end` + `idle` composite shutdown emit must NOT
  /// re-create the record. A pid-less idle re-seed would be skipped by the
  /// liveness sweep and pinned until surface close.
  private static func applyActivity(
    _ activity: Activity, event: AgentHookEvent, key: PresenceKey, into state: inout State
  ) -> (changed: Bool, flip: (from: Activity, to: Activity)?) {
    if var record = state.records[key] {
      guard record.activity != activity else { return (false, nil) }
      let previous = record.activity
      record.activity = activity
      state.records[key] = record
      return (true, (previous, activity))
    }
    guard event.pid == nil, activity != .idle else { return (false, nil) }
    state.records[key] = PresenceRecord(activity: activity, pids: [])
    insertPresence(agent: key.agent, surfaceID: event.surfaceID, in: &state)
    // Fresh record, no prior activity to have transitioned from.
    return (true, nil)
  }

  private static func drop(surfaces: Set<UUID>, from state: inout State) {
    for id in surfaces { state.bySurface.removeValue(forKey: id) }
    // Only drop keys for closed surfaces — avoid rebuilding the whole dict
    // when a bulk prune closes many surfaces under a large roster.
    if surfaces.count == 1, let only = surfaces.first {
      state.records = state.records.filter { $0.key.surfaceID != only }
    } else {
      state.records = state.records.filter { !surfaces.contains($0.key.surfaceID) }
    }
  }

  /// Pure liveness check; returns only keys whose alive subset diverges from the snapshot.
  nonisolated static func liveness(forSnapshot snapshot: [PresenceKey: Set<pid_t>]) -> [PresenceKey: Set<pid_t>] {
    var result: [PresenceKey: Set<pid_t>] = [:]
    for (key, pids) in snapshot {
      // `kill(0, 0)` / `kill(-N, 0)` succeed against the caller's process group; reject non-positive pids.
      let alive = pids.filter { $0 > 0 && kill($0, 0) == 0 }
      if alive != pids {
        result[key] = alive
      }
    }
    return result
  }

  /// Apply the liveness delta back to state. Pids added between snapshot capture and apply
  /// (e.g. a `.sessionStart` that landed during the off-main hop) are preserved.
  private static func applyLiveness(
    delta: [PresenceKey: Set<pid_t>],
    snapshot: [PresenceKey: Set<pid_t>],
    into state: inout State
  ) -> Set<UUID> {
    var dirtySurfaces: Set<UUID> = []
    for (key, alive) in delta {
      guard var record = state.records[key] else { continue }
      let snapshotPids = snapshot[key] ?? []
      // Subtract only the pids the sweep proved dead; current additions/removals stay authoritative.
      let deadPids = snapshotPids.subtracting(alive)
      let next = record.pids.subtracting(deadPids)
      if next.isEmpty {
        state.records.removeValue(forKey: key)
        removePresence(agent: key.agent, surfaceID: key.surfaceID, in: &state)
        dirtySurfaces.insert(key.surfaceID)
      } else if record.pids != next {
        record.pids = next
        state.records[key] = record
        dirtySurfaces.insert(key.surfaceID)
      }
    }
    return dirtySurfaces
  }

  struct StagedRestore: Sendable {
    let pids: Set<pid_t>
    let activity: Activity
  }

  /// Build the staged-restore dict from persisted layouts. No `kill(2)` here;
  /// liveness check is the caller's responsibility in `.run`.
  nonisolated static func stageRestore(
    fromLayouts layouts: some Sequence<TerminalLayoutSnapshot>
  ) -> [PresenceKey: StagedRestore] {
    var staged: [PresenceKey: StagedRestore] = [:]
    for layout in layouts {
      for (surfaceID, records) in layout.allAgentRecords() {
        for record in records {
          guard let agent = SkillAgent(rawValue: record.agent) else { continue }
          // Pid-less OSC records aren't restore-durable: they persist with no
          // pid, so they drop here and re-seed on the next OSC event post-relaunch.
          let pids = Set(record.pids.filter { $0 > 0 })
          guard !pids.isEmpty else { continue }
          let activity = Activity(rawValue: record.activity) ?? .idle
          staged[PresenceKey(agent: agent, surfaceID: surfaceID)] =
            StagedRestore(pids: pids, activity: activity)
        }
      }
    }
    return staged
  }

  /// Rejects non-positive pids; `kill(0, ...)` targets process groups, not
  /// individual processes.
  nonisolated static func isAlive(_ pid: pid_t) -> Bool {
    pid > 0 && kill(pid, 0) == 0
  }

  /// A hook event that raced ahead of the restore takes precedence.
  private static func applyRestore(
    records: [PresenceKey: RestoredRecord],
    into state: inout State
  ) -> Set<UUID> {
    var dirtySurfaces: Set<UUID> = []
    for (key, record) in records {
      if state.records[key] != nil { continue }
      // Restored records always have alive pids (pid-less OSC records are dropped in stageRestore).
      state.records[key] = PresenceRecord(activity: record.activity, pids: record.alivePids)
      insertPresence(agent: key.agent, surfaceID: key.surfaceID, in: &state)
      dirtySurfaces.insert(key.surfaceID)
    }
    return dirtySurfaces
  }

  /// Incremental `bySurface` maintenance — avoids rescanning all records per
  /// dirty surface on every session start/end / liveness eviction.
  private static func insertPresence(agent: SkillAgent, surfaceID: UUID, in state: inout State) {
    state.bySurface[surfaceID, default: []].insert(agent)
  }

  private static func removePresence(agent: SkillAgent, surfaceID: UUID, in state: inout State) {
    guard var agents = state.bySurface[surfaceID] else { return }
    agents.remove(agent)
    if agents.isEmpty {
      state.bySurface.removeValue(forKey: surfaceID)
    } else {
      state.bySurface[surfaceID] = agents
    }
  }
}

extension AgentPresenceFeature.State {
  /// Sorted output so the persisted JSON stays diff-stable.
  func agentsBySurface() -> [UUID: [TerminalLayoutSnapshot.SurfaceAgentRecord]] {
    AgentPresenceFeature.agentsBySurface(records: records)
  }
}

extension AgentPresenceFeature {
  /// Pure, `nonisolated` core of `State.agentsBySurface()`. Taking the (Sendable) `records` dict
  /// by value lets a debounced effect capture just `records` and run this AFTER its sleep off the
  /// main actor, so presence storms that get cancelled by a newer delta pay nothing for the
  /// sort/allocation that only the surviving tick needs to persist.
  nonisolated static func agentsBySurface(
    records: [PresenceKey: PresenceRecord]
  ) -> [UUID: [TerminalLayoutSnapshot.SurfaceAgentRecord]] {
    guard !records.isEmpty else { return [:] }
    var result: [UUID: [TerminalLayoutSnapshot.SurfaceAgentRecord]] = [:]
    for (key, record) in records {
      let entry = TerminalLayoutSnapshot.SurfaceAgentRecord(
        agent: key.agent.rawValue,
        pids: record.pids.sorted(),
        activity: record.activity.rawValue
      )
      result[key.surfaceID, default: []].append(entry)
    }
    for (id, entries) in result {
      result[id] = entries.sorted { $0.agent < $1.agent }
    }
    return result
  }
}

extension AgentPresenceFeature.State {
  /// Agents on a single surface. Empty when badges are disabled by the user.
  func agents(forSurface id: UUID, badgesEnabled: Bool) -> Set<SkillAgent> {
    guard badgesEnabled else { return [] }
    return bySurface[id] ?? []
  }

  /// One `AgentInstance` per (surface, agent) pair across the given surface list.
  /// Duplicates preserved (a tab hosting two surfaces both
  /// running Claude shows two Claude badges). Sorted with awaiting-input
  /// instances first (contrast-flipped badges lead the row) then by agent
  /// rawValue so iteration is stable across renders.
  func agents(
    across surfaceIDs: some Sequence<UUID>,
    badgesEnabled: Bool,
  ) -> [AgentPresenceFeature.AgentInstance] {
    guard badgesEnabled else { return [] }
    return
      surfaceIDs
      .flatMap { surfaceID -> [AgentPresenceFeature.AgentInstance] in
        (bySurface[surfaceID] ?? []).map { agent in
          let activity =
            records[AgentPresenceFeature.PresenceKey(agent: agent, surfaceID: surfaceID)]?.activity ?? .idle
          return AgentPresenceFeature.AgentInstance(agent: agent, surfaceID: surfaceID, activity: activity)
        }
      }
      .sorted { lhs, rhs in
        if lhs.awaitingInput != rhs.awaitingInput { return lhs.awaitingInput }
        if lhs.agent.rawValue != rhs.agent.rawValue { return lhs.agent.rawValue < rhs.agent.rawValue }
        // UUID is Comparable — avoid `uuidString` allocations on every fan-out sort.
        return lhs.surfaceID < rhs.surfaceID
      }
  }

  /// Any agent on any of the listed surfaces is actively working (`.busy`).
  /// Awaiting-input is excluded: the agent is parked on the user, not working,
  /// so it must not shimmer (the inverted badge already signals that state).
  /// Drives the sidebar shimmer alongside Ghostty progress state; not gated by
  /// the badge toggle since the shimmer is a generic "this worktree is doing
  /// work" signal independent of avatar visibility.
  func hasActivity(in surfaceIDs: some Sequence<UUID>) -> Bool {
    let surfaceSet = Set(surfaceIDs)
    return records.contains { entry in
      entry.value.activity == .busy && surfaceSet.contains(entry.key.surfaceID)
    }
  }

  /// Surface IDs with at least one `.busy` agent, in one pass over `records`.
  /// Callers testing MANY surface-lists for activity (the presence fan-out builds this once and
  /// then does O(list) membership per row) avoid `hasActivity(in:)`'s per-call full scan of
  /// `records`, which is O(rows × records) across the loop.
  func busySurfaceIDs() -> Set<UUID> {
    var result: Set<UUID> = []
    for (key, record) in records where record.activity == .busy {
      result.insert(key.surfaceID)
    }
    return result
  }
}
