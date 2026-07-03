import OSLog

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
      logger.notice("\(message, privacy: .public)")
    #endif
  }

  public func info(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #else
      logger.notice("\(message, privacy: .public)")
    #endif
  }

  public func warning(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #else
      logger.warning("\(message, privacy: .public)")
    #endif
  }

  public func error(_ message: String) {
    #if DEBUG
      print("[\(category)] \(message)")
    #else
      logger.error("\(message, privacy: .public)")
    #endif
  }
}
