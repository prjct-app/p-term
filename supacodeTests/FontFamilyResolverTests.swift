import Testing

@testable import SupacodeSettingsShared

/// Exercises `FontFamilyResolver` against fonts guaranteed present on every
/// macOS install (Menlo/Helvetica ship with the OS), so these don't depend on
/// third-party fonts being installed on the test machine.
@MainActor
struct FontFamilyResolverTests {
  @Test func isInstalledIsTrueForBuiltInFamilies() {
    #expect(FontFamilyResolver.isInstalled("Menlo"))
    #expect(FontFamilyResolver.isInstalled("Helvetica"))
  }

  @Test func isInstalledIsFalseForUnknownFamily() {
    #expect(!FontFamilyResolver.isInstalled("Definitely Not A Real Font Family"))
  }

  @Test func regularFontNameResolvesForBuiltInFamily() {
    #expect(FontFamilyResolver.regularFontName(forFamily: "Menlo") != nil)
  }

  @Test func regularFontNameReturnsNilForUnknownFamily() {
    #expect(FontFamilyResolver.regularFontName(forFamily: "Definitely Not A Real Font Family") == nil)
  }

  @Test func isMonospaceDistinguishesMenloFromHelvetica() {
    #expect(FontFamilyResolver.isMonospace(family: "Menlo"))
    #expect(!FontFamilyResolver.isMonospace(family: "Helvetica"))
  }

  @Test func allFamiliesIsSortedAndIncludesBuiltIns() {
    let families = FontFamilyResolver.allFamilies
    #expect(families.contains("Menlo"))
    #expect(families == families.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
  }
}
