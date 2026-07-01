import AppKit
import CoreText

/// Thin `NSFontManager` wrapper resolving user-selected font families to
/// concrete font names and traits. Separate from `AppFontSelection`'s
/// `Codable` because installed fonts can change between app launches without
/// the persisted settings file ever changing — availability is a runtime
/// check, not a decode-time one.
public nonisolated enum FontFamilyResolver {
  /// Every installed font family, sorted for stable picker ordering.
  public static var allFamilies: [String] {
    NSFontManager.shared.availableFontFamilies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  public static func isInstalled(_ family: String) -> Bool {
    NSFontManager.shared.availableFontFamilies.contains(family)
  }

  /// The family's "Regular" (or closest) member's font name, suitable for
  /// `SwiftUI.Font.custom(name:size:)`, which wants a font name, not a
  /// family name.
  public static func regularFontName(forFamily family: String) -> String? {
    guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family), !members.isEmpty else {
      return nil
    }
    // Members are [fontName, displayName, weight, traits]; prefer a
    // non-italic, non-bold member (regular weight), falling back to the first.
    let regular = members.first { member in
      guard member.count >= 4, let traits = member[3] as? Int else { return false }
      let mask = NSFontTraitMask(rawValue: UInt(traits))
      return !mask.contains(.italicFontMask) && !mask.contains(.boldFontMask)
    }
    let chosen = regular ?? members[0]
    return chosen.first as? String
  }

  /// Whether the family's regular member is a fixed-pitch (monospace) font.
  public static func isMonospace(family: String) -> Bool {
    guard let name = regularFontName(forFamily: family) else { return false }
    let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, 12)
    guard let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any],
      let symbolic = traits[kCTFontSymbolicTrait] as? UInt32
    else {
      return false
    }
    return symbolic & CTFontSymbolicTraits.traitMonoSpace.rawValue != 0
  }
}
