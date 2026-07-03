import Foundation

enum GitHubOwnerAvatar {
  static func url(for rootURL: URL, gitClient: GitClientDependency) async -> URL? {
    guard let info = await gitClient.remoteInfo(rootURL) else { return nil }
    return URL(string: "https://github.com/\(info.owner).png?size=64")
  }
}
