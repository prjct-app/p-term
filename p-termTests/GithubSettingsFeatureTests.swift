import ComposableArchitecture
import Foundation
import Testing

@testable import p_term

@MainActor
struct GithubSettingsFeatureTests {
  @Test func loadReportsAuthenticated() async {
    let store = TestStore(initialState: GithubSettingsFeature.State()) {
      GithubSettingsFeature()
    } withDependencies: {
      $0[GithubIntegrationClient.self].isAvailable = { true }
      $0[GithubCLIClient.self].authStatus = { GithubAuthStatus(username: "khoi", host: "github.com") }
    }

    await store.send(.load)
    await store.receive(\.statusLoaded) {
      $0.status = .authenticated(username: "khoi", host: "github.com")
    }
  }

  @Test func loadReportsUnavailableWhenCliMissing() async {
    let store = TestStore(initialState: GithubSettingsFeature.State()) {
      GithubSettingsFeature()
    } withDependencies: {
      $0[GithubIntegrationClient.self].isAvailable = { false }
    }

    await store.send(.load)
    await store.receive(\.statusLoaded) { $0.status = .unavailable }
  }

  @Test func loadReportsNotAuthenticatedWhenNoStatus() async {
    let store = TestStore(initialState: GithubSettingsFeature.State()) {
      GithubSettingsFeature()
    } withDependencies: {
      $0[GithubIntegrationClient.self].isAvailable = { true }
      $0[GithubCLIClient.self].authStatus = { nil }
    }

    await store.send(.load)
    await store.receive(\.statusLoaded) { $0.status = .notAuthenticated }
  }

  @Test func loadMapsOutdatedError() async {
    let store = TestStore(initialState: GithubSettingsFeature.State()) {
      GithubSettingsFeature()
    } withDependencies: {
      $0[GithubIntegrationClient.self].isAvailable = { true }
      $0[GithubCLIClient.self].authStatus = { throw GithubCLIError.outdated }
    }

    await store.send(.load)
    await store.receive(\.statusLoaded) { $0.status = .outdated }
  }
}
