import SwiftUI

/// Semantic typography tokens for the app's own UI. Each role reads
/// `AppFontRegistry.shared.resolvedUIFontName`: when the user has selected a
/// custom UI font, text renders in that family at Apple's documented default
/// point size for the role, still scaled by Dynamic Type via `relativeTo:`;
/// otherwise it falls back to the plain system text style. This is the first
/// real implementation of the "Use Dynamic Type, avoid hardcoded font sizes"
/// UX standard — previously aspirational, with no code enforcing it.
///
/// Every `.font(.body)`-style call site in `supacode` should read
/// `AppTypography.body` instead, so a font selection applies uniformly rather
/// than to only some text.
@MainActor
public enum AppTypography {
  public static var body: Font { role(.body, size: 13) }
  public static var callout: Font { role(.callout, size: 12) }
  public static var subheadline: Font { role(.subheadline, size: 11) }
  public static var footnote: Font { role(.footnote, size: 10) }
  public static var caption: Font { role(.caption, size: 10) }
  public static var caption2: Font { role(.caption2, size: 10) }
  public static var headline: Font { role(.headline, size: 13) }
  public static var title: Font { role(.title, size: 22) }
  public static var title2: Font { role(.title2, size: 17) }
  public static var title3: Font { role(.title3, size: 15) }

  private static func role(_ style: Font.TextStyle, size: CGFloat) -> Font {
    guard let name = AppFontRegistry.shared.resolvedUIFontName else { return .system(style) }
    return .custom(name, size: size, relativeTo: style)
  }
}
