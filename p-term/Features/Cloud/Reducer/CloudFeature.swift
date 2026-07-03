import ComposableArchitecture
import Foundation

/// Drives the native Cloud surface. All side effects (status, login, Keychain) go through
/// `CloudAPIClient` — the reducer only orchestrates, never touches the network / Keychain / a
/// subprocess directly (SOLID). p/term stays free: sign in / view state here, pay for sync in the
/// service.
@Reducer
struct CloudFeature {
  @ObservableState
  struct State: Equatable {
    var status: CloudStatus = .unknown
    var isRefreshing = false
    var isSigningIn = false
    /// The focused project's working directory — cloud status is per-project. Set by the parent.
    var projectDirectory: URL?
  }

  enum Action: Equatable {
    case onAppear
    case refresh
    case statusLoaded(CloudStatus)
    case signInTapped
    /// The loopback sign-in flow finished (device key captured + persisted, or not).
    case signInFinished(success: Bool)
    /// A `pk_live_*` device key arrived from the `p-term://cloud/auth` deeplink fallback.
    case loginCompleted(token: String)
    case signOutTapped
  }

  @Dependency(CloudAPIClient.self) private var cloud

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .onAppear, .refresh:
        state.isRefreshing = true
        let projectDirectory = state.projectDirectory
        return .run { send in
          await send(.statusLoaded(cloud.status(projectDirectory)))
        }

      case .statusLoaded(let status):
        state.isRefreshing = false
        state.status = status
        return .none

      case .signInTapped:
        state.isSigningIn = true
        return .run { send in
          await send(.signInFinished(success: await cloud.beginLogin()))
        }

      case .signInFinished(let success):
        state.isSigningIn = false
        return success ? .send(.refresh) : .none

      case .loginCompleted(let token):
        state.isSigningIn = false
        return .run { send in
          guard cloud.completeLogin(token) else { return }
          await send(.refresh)
        }

      case .signOutTapped:
        return .run { send in
          cloud.logout()
          await send(.refresh)
        }
      }
    }
  }
}
