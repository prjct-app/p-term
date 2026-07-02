import ComposableArchitecture
import Foundation
import Testing

@testable import p_term

@MainActor
struct ActivityFeedFeatureTests {
  private func makeStore() -> TestStoreOf<ActivityFeedFeature> {
    let store = TestStore(initialState: ActivityFeedFeature.State()) {
      ActivityFeedFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.date = .constant(Date(timeIntervalSince1970: 0))
    }
    store.exhaustivity = .off
    return store
  }

  @Test func recordPrependsNewestFirst() async {
    let store = makeStore()
    await store.send(.record(kind: .notification, title: "First", subtitle: nil, worktreeID: nil))
    await store.send(
      .record(kind: .scriptFinished(success: true), title: "Second", subtitle: "ok", worktreeID: nil))

    #expect(store.state.events.map(\.title) == ["Second", "First"])
    #expect(store.state.events.first?.subtitle == "ok")
  }

  @Test func capsAtMaxEventsKeepingNewest() async {
    let store = makeStore()
    let overflow = ActivityFeedFeature.maxEvents + 5
    for index in 0..<overflow {
      await store.send(.record(kind: .notification, title: "e\(index)", subtitle: nil, worktreeID: nil))
    }

    #expect(store.state.events.count == ActivityFeedFeature.maxEvents)
    #expect(store.state.events.first?.title == "e\(overflow - 1)")
    #expect(!store.state.events.contains { $0.title == "e0" })
  }

  @Test func clearEmptiesTheFeed() async {
    let store = makeStore()
    await store.send(.record(kind: .notification, title: "x", subtitle: nil, worktreeID: nil))
    await store.send(.clear)

    #expect(store.state.events.isEmpty)
  }

  @Test func activatingAnEventWithAWorktreeEmitsJump() async {
    let store = makeStore()
    let worktreeID: Worktree.ID = "/repo/wt"
    await store.send(.record(kind: .notification, title: "x", subtitle: nil, worktreeID: worktreeID))
    let event = store.state.events[0]

    await store.send(.activate(event))
    await store.receive(\.delegate.jumpToWorktree)
  }

  @Test func activatingAnAppWideEventDoesNothing() async {
    let store = makeStore()
    await store.send(.record(kind: .notification, title: "x", subtitle: nil, worktreeID: nil))
    let event = store.state.events[0]

    // No worktree → no jump delegate. (Exhaustivity is off, so assert no crash + still present.)
    await store.send(.activate(event))
    #expect(store.state.events.count == 1)
  }

  @Test func filterRestrictsVisibleEventsToOneWorktree() async {
    let store = makeStore()
    let worktreeA: Worktree.ID = "/repo/a"
    let worktreeB: Worktree.ID = "/repo/b"
    await store.send(.record(kind: .notification, title: "A1", subtitle: nil, worktreeID: worktreeA))
    await store.send(.record(kind: .notification, title: "B1", subtitle: nil, worktreeID: worktreeB))
    await store.send(.record(kind: .notification, title: "App", subtitle: nil, worktreeID: nil))

    // Options are the distinct worktrees present, newest-first: b then a.
    #expect(store.state.worktreeFilterOptions == [worktreeB, worktreeA])

    await store.send(.setFilter(worktreeA))
    #expect(store.state.visibleEvents.map(\.title) == ["A1"])

    await store.send(.setFilter(nil))
    #expect(store.state.visibleEvents.count == 3)
  }

  @Test func clearResetsTheFilter() async {
    let store = makeStore()
    let worktreeA: Worktree.ID = "/repo/a"
    await store.send(.record(kind: .notification, title: "A1", subtitle: nil, worktreeID: worktreeA))
    await store.send(.setFilter(worktreeA))
    await store.send(.clear)

    #expect(store.state.filterWorktreeID == nil)
    #expect(store.state.visibleEvents.isEmpty)
  }
}
