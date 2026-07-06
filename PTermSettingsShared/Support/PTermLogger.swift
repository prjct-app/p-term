import OSLog

/// Release logging redacts interpolated messages (`privacy: .private`) so paths,
/// branch/repo names, and any token that slips into a message are not written to
/// the persistent unified log in cleartext.
public nonisolated struct PTermLogger: Sendable {
  private let category: String
  #if !DEBUG
    private let logger: Logger
  #endif

  public init(_ category: String) {
    self.category = category
    #if !DEBUG
      // This module is linked by the non-app CLI target too, whose bare executable can have a nil
      // `bundleIdentifier`; force-unwrapping would crash the CLI on its first log call.
      self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.prjct.p-term", category: category)
    #endif
  }

  public func debug(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #else
      logger.notice("\(message, privacy: .private)")
    #endif
  }

  public func info(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #else
      logger.notice("\(message, privacy: .private)")
    #endif
  }

  public func warning(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #else
      logger.warning("\(message, privacy: .private)")
    #endif
  }

  public func error(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #else
      logger.error("\(message, privacy: .private)")
    #endif
  }
}
