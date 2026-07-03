import ComposableArchitecture
import Foundation
import Testing

@testable import p_term

@MainActor
struct CloudFeatureTests {
  private nonisolated static let authedUnlinked = CloudStatus(
    isAuthenticated: true, isLinked: false, isPaused: false, pendingEvents: 3, realtime: nil,
    lastSync: nil)

  @Test func onAppearLoadsStatus() async {
    let store = TestStore(initialState: CloudFeature.State()) {
      CloudFeature()
    } withDependencies: {
      $0[CloudAPIClient.self].status = { _ in Self.authedUnlinked }
    }

    await store.send(.onAppear) { $0.isRefreshing = true }
    await store.receive(\.statusLoaded) {
      $0.isRefreshing = false
      $0.status = Self.authedUnlinked
    }
  }

  @Test func signInRunsLoginThenRefreshesOnSuccess() async {
    let attempted = LockIsolated(false)
    let store = TestStore(initialState: CloudFeature.State()) {
      CloudFeature()
    } withDependencies: {
      $0[CloudAPIClient.self].beginLogin = {
        attempted.setValue(true)
        return true
      }
      $0[CloudAPIClient.self].status = { _ in Self.authedUnlinked }
    }
    store.exhaustivity = .off

    await store.send(.signInTapped) { $0.isSigningIn = true }
    await store.receive(\.signInFinished) { $0.isSigningIn = false }
    await store.receive(\.refresh)
    #expect(attempted.value)
  }

  @Test func signInFailureDoesNotRefresh() async {
    let store = TestStore(initialState: CloudFeature.State()) {
      CloudFeature()
    } withDependencies: {
      $0[CloudAPIClient.self].beginLogin = { false }
    }
    store.exhaustivity = .off

    await store.send(.signInTapped) { $0.isSigningIn = true }
    await store.receive(\.signInFinished) { $0.isSigningIn = false }
    await store.finish()
  }

  @Test func loginCompletedPersistsTokenAndRefreshes() async {
    let saved = LockIsolated<String?>(nil)
    let store = TestStore(initialState: CloudFeature.State(isSigningIn: true)) {
      CloudFeature()
    } withDependencies: {
      $0[CloudAPIClient.self].completeLogin = { token in
        saved.setValue(token)
        return true
      }
      $0[CloudAPIClient.self].status = { _ in Self.authedUnlinked }
    }
    store.exhaustivity = .off

    await store.send(.loginCompleted(token: "pk_live_abc")) { $0.isSigningIn = false }
    await store.receive(\.refresh)
    await store.receive(\.statusLoaded)
    #expect(saved.value == "pk_live_abc")
  }

  @Test func signOutClearsSessionAndRefreshes() async {
    let loggedOut = LockIsolated(false)
    let store = TestStore(initialState: CloudFeature.State()) {
      CloudFeature()
    } withDependencies: {
      $0[CloudAPIClient.self].logout = { loggedOut.setValue(true) }
      $0[CloudAPIClient.self].status = { _ in .unknown }
    }
    store.exhaustivity = .off

    await store.send(.signOutTapped)
    await store.receive(\.refresh)
    #expect(loggedOut.value)
  }
}
