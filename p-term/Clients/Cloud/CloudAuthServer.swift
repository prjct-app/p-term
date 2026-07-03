import Foundation
import Network

/// Loopback HTTP server that captures the prjct Cloud sign-in callback. The web opens at
/// `prjct.app/auth/cli?port=<n>` and, after login, requests
/// `http://127.0.0.1:<n>/callback?key=pk_live_…&user_id=…&device_id=…`. Single-shot, loopback-only,
/// times out. Isolated so `CloudAPIClient` stays declarative.
enum CloudAuthServer {
  enum AuthError: Error, Equatable { case listenerFailed }

  /// Start a loopback listener, hand the chosen port to `openBrowser`, and resolve with the first
  /// valid `/callback?key=…` request. Throws on timeout / cancellation / listener failure.
  static func awaitCallback(
    timeout: Duration = .seconds(180),
    openBrowser: @escaping @Sendable (_ port: Int) -> Void
  ) async throws -> CloudAuthCallback {
    let box = CloudAuthListenerBox()
    return try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: CloudAuthCallback.self) { group in
        group.addTask { try await box.run(openBrowser: openBrowser) }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw CancellationError()
        }
        defer {
          group.cancelAll()
          box.cancel()
        }
        guard let result = try await group.next() else { throw AuthError.listenerFailed }
        return result
      }
    } onCancel: {
      box.cancel()
    }
  }
}

/// Owns the NWListener + the single-resume continuation, guarded by a lock (NWListener callbacks
/// arrive on a background queue). `@unchecked Sendable` because the lock provides the safety.
private final class CloudAuthListenerBox: @unchecked Sendable {
  private let lock = NSLock()
  private let queue = DispatchQueue(label: "app.prjct.p-term.cloud-auth")
  private var listener: NWListener?
  private var continuation: CheckedContinuation<CloudAuthCallback, Error>?
  private var finished = false

  func run(openBrowser: @escaping @Sendable (Int) -> Void) async throws -> CloudAuthCallback {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      self.continuation = continuation
      lock.unlock()
      start(openBrowser: openBrowser)
    }
  }

  private func start(openBrowser: @escaping @Sendable (Int) -> Void) {
    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .loopback
    parameters.allowLocalEndpointReuse = true
    guard let listener = try? NWListener(using: parameters) else {
      finish(.failure(CloudAuthServer.AuthError.listenerFailed))
      return
    }
    lock.lock()
    self.listener = listener
    lock.unlock()

    listener.stateUpdateHandler = { state in
      switch state {
      case .ready:
        if let port = listener.port?.rawValue { openBrowser(Int(port)) }
      case .failed:
        self.finish(.failure(CloudAuthServer.AuthError.listenerFailed))
      default:
        break
      }
    }
    listener.newConnectionHandler = { [weak self] connection in
      self?.handle(connection)
    }
    listener.start(queue: queue)
  }

  private func handle(_ connection: NWConnection) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
      guard let self else { return }
      let requestLine =
        data
        .flatMap { String(data: $0, encoding: .utf8) }?
        .split(separator: "\r\n").first
        .map(String.init)
      if let requestLine, let callback = CloudAuthCallback.parse(requestLine: requestLine) {
        self.respond(on: connection, ok: true)
        self.finish(.success(callback))
      } else {
        self.respond(on: connection, ok: false)
      }
    }
  }

  private func respond(on connection: NWConnection, ok: Bool) {
    let heading = ok ? "Signed in — you can return to p/term." : "Sign-in failed. Try again from p/term."
    let html =
      "<html><body style=\"font-family:-apple-system;padding:3rem;text-align:center\"><h2>\(heading)</h2></body></html>"
    let response =
      "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\(html)"
    connection.send(
      content: Data(response.utf8),
      completion: .contentProcessed { _ in connection.cancel() })
  }

  func cancel() {
    finish(.failure(CancellationError()))
  }

  private func finish(_ result: Result<CloudAuthCallback, Error>) {
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }
    finished = true
    let continuation = self.continuation
    let listener = self.listener
    self.continuation = nil
    self.listener = nil
    lock.unlock()

    listener?.cancel()
    continuation?.resume(with: result)
  }
}
