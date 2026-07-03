import Foundation
import Testing

@testable import p_term

struct CloudStatusParserTests {
  @Test func parsesTheCliStatusOutput() {
    let output = """
      Cloud — local-only (run `prjct cloud link`)
        Authenticated: yes
        Linked: no
        Realtime: n/a
        Pending events: 205
        Last sync: never
      """
    let status = CloudStatus.parse(cliOutput: output)

    #expect(status.isAuthenticated)
    #expect(!status.isLinked)
    #expect(status.pendingEvents == 205)
    #expect(status.realtime == "n/a")
    #expect(status.lastSync == "never")
    #expect(status.presentation == .signedInUnlinked)
  }

  @Test func parsesLinkedSyncingProject() {
    let output = """
        Authenticated: yes
        Linked: yes
        Realtime: connected
        Pending events: 0
        Last sync: 2026-07-03T00:00:00Z
      """
    let status = CloudStatus.parse(cliOutput: output)

    #expect(status.isLinked)
    #expect(!status.isPaused)
    #expect(status.presentation == .syncing(pending: 0))
  }

  @Test func emptyOutputIsSignedOutUnknown() {
    let status = CloudStatus.parse(cliOutput: "")

    #expect(status == .unknown)
    #expect(status.presentation == .signedOut)
  }

  @Test func detectsPausedFromHeader() {
    let output = """
      Cloud — paused
        Authenticated: yes
        Linked: yes
      """
    let status = CloudStatus.parse(cliOutput: output)

    #expect(status.isPaused)
    #expect(status.presentation == .paused)
  }
}
