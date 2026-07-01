import ArgumentParser

struct SocketCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "socket",
    abstract: "List active p/term sockets."
  )

  func run() throws {
    let sockets = try SocketDiscovery.listAll()
    guard !sockets.isEmpty else {
      throw ValidationError("No p/term sockets found. Is the app running?")
    }
    for path in sockets {
      print(path)
    }
  }
}
