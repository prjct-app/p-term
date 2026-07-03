import ComposableArchitecture
import Foundation
import Testing

@testable import p_term

@MainActor
struct MemoryFeatureTests {
  private static let sample = [
    MemoryEntry(id: "mem_1", type: "decision", content: "Use TCA everywhere")
  ]

  @Test func debouncedQueryRunsSearchAndLoads() async {
    let clock = TestClock()
    let store = TestStore(initialState: MemoryFeature.State()) {
      MemoryFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0[MemoryClient.self].search = { _, _ in Self.sample }
    }

    await store.send(.queryChanged("tca")) { $0.query = "tca" }
    await clock.advance(by: .milliseconds(250))
    await store.receive(\.search) { $0.isSearching = true }
    await store.receive(\.loaded) {
      $0.isSearching = false
      $0.entries = Self.sample
    }
  }

  @Test func rapidTypingDebouncesToOneSearch() async {
    let clock = TestClock()
    let searchCount = LockIsolated(0)
    let store = TestStore(initialState: MemoryFeature.State()) {
      MemoryFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0[MemoryClient.self].search = { _, _ in
        searchCount.withValue { $0 += 1 }
        return []
      }
    }
    store.exhaustivity = .off

    await store.send(.queryChanged("t"))
    await store.send(.queryChanged("tc"))
    await store.send(.queryChanged("tca"))
    await clock.advance(by: .milliseconds(250))
    await store.skipReceivedActions()

    #expect(searchCount.value == 1)
  }

  @Test func emptyQueryClearsEntries() async {
    let store = TestStore(initialState: MemoryFeature.State(query: "x", entries: Self.sample)) {
      MemoryFeature()
    } withDependencies: {
      $0.continuousClock = ImmediateClock()
      $0[MemoryClient.self].search = { _, _ in Self.sample }
    }
    store.exhaustivity = .off

    await store.send(.queryChanged("   ")) { $0.query = "   " }
    await store.receive(\.search) {
      $0.entries = []
      $0.isSearching = false
    }
  }
}
