import ComposableArchitecture
import Foundation

/// GitHub CLI status for the Settings pane. Converts the former `@Observable GithubSettingsViewModel`
/// (a stray MVVM view model) into TCA so the whole app is one architecture: state changes only via
/// actions through a pure reducer, the two GitHub clients are reached only from an effect.
@Reducer
struct GithubSettingsFeature {
  @ObservableState
  struct State: Equatable {
    var status: Status = .loading

    enum Status: Equatable, Sendable {
      case loading
      case unavailable
      case outdated
      case notAuthenticated
      case authenticated(username: String, host: String)
      case error(String)
    }
  }

  enum Action: Equatable {
    /// Re-check the GitHub CLI (on appear / when integration is toggled).
    case load
    case statusLoaded(State.Status)
  }

  @Dependency(GithubIntegrationClient.self) private var githubIntegration
  @Dependency(GithubCLIClient.self) private var githubCLI

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .load:
        state.status = .loading
        return .run { send in
          await send(.statusLoaded(Self.resolveStatus(githubIntegration: githubIntegration, githubCLI: githubCLI)))
        }

      case .statusLoaded(let status):
        state.status = status
        return .none
      }
    }
  }

  /// The former view model's `load()` body — pure aside from the two injected clients, so it stays a
  /// static the effect calls (no free function polluting the namespace).
  private static func resolveStatus(
    githubIntegration: GithubIntegrationClient,
    githubCLI: GithubCLIClient
  ) async -> State.Status {
    guard await githubIntegration.isAvailable() else { return .unavailable }
    do {
      if let status = try await githubCLI.authStatus() {
        return .authenticated(username: status.username, host: status.host)
      }
      return .notAuthenticated
    } catch let error as GithubCLIError {
      switch error {
      case .outdated: return .outdated
      case .unavailable: return .unavailable
      case .gatewayTimeout: return .error(error.localizedDescription)
      case .commandFailed(let message): return .error(message)
      }
    } catch {
      return .error(error.localizedDescription)
    }
  }
}
