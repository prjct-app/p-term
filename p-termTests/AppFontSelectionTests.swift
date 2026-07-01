import Foundation
import Testing

@testable import PTermSettingsShared

@MainActor
struct AppFontSelectionTests {
  @Test func parseTreatsEmptyAndSystemAsSystemDefault() {
    #expect(AppFontSelection.parse("") == .systemDefault)
    #expect(AppFontSelection.parse("system") == .systemDefault)
  }

  @Test func parseTreatsAnyOtherStringAsCustomFamilyName() {
    #expect(AppFontSelection.parse("Menlo") == .custom(familyName: "Menlo"))
    #expect(AppFontSelection.parse("not-a-real-font") == .custom(familyName: "not-a-real-font"))
  }

  @Test func decoderNeverThrowsOnUnrecognizedInput() throws {
    let json = Data("\"whatever-family\"".utf8)
    let decoded = try JSONDecoder().decode(AppFontSelection.self, from: json)
    #expect(decoded == .custom(familyName: "whatever-family"))
  }

  @Test(
    arguments: [
      (AppFontSelection.systemDefault, "system"),
      (.custom(familyName: "Menlo"), "Menlo"),
    ]
  )
  func codableRoundTripsAllCases(selection: AppFontSelection, rawValue: String) throws {
    let encoded = try JSONEncoder().encode(selection)
    #expect(String(bytes: encoded, encoding: .utf8) == "\"\(rawValue)\"")
    let decoded = try JSONDecoder().decode(AppFontSelection.self, from: encoded)
    #expect(decoded == selection)
  }

  @Test func familyNameReturnsNilForSystemDefault() {
    #expect(AppFontSelection.systemDefault.familyName == nil)
    #expect(AppFontSelection.custom(familyName: "Menlo").familyName == "Menlo")
  }

  @Test func isCustomReflectsCase() {
    #expect(!AppFontSelection.systemDefault.isCustom)
    #expect(AppFontSelection.custom(familyName: "Menlo").isCustom)
  }
}
