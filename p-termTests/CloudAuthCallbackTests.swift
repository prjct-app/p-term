import Foundation
import Testing

@testable import p_term

struct CloudAuthCallbackTests {
  @Test func parsesKeyAndMetadataFromCallbackRequestLine() {
    let line = "GET /callback?key=pk_live_abc&user_id=u1&email=a@b.co&device_id=d9 HTTP/1.1"
    let callback = CloudAuthCallback.parse(requestLine: line)

    #expect(callback == CloudAuthCallback(key: "pk_live_abc", userId: "u1", email: "a@b.co", deviceId: "d9"))
  }

  @Test func requiresCallbackPathAndKey() {
    #expect(CloudAuthCallback.parse(requestLine: "GET /favicon.ico HTTP/1.1") == nil)
    #expect(CloudAuthCallback.parse(requestLine: "GET /callback?user_id=u1 HTTP/1.1") == nil)
    #expect(CloudAuthCallback.parse(requestLine: "garbage") == nil)
  }

  @Test func keyWithoutOptionalMetadataStillParses() {
    let callback = CloudAuthCallback.parse(requestLine: "GET /callback?key=pk_live_x HTTP/1.1")
    #expect(callback?.key == "pk_live_x")
    #expect(callback?.userId == nil)
  }
}
