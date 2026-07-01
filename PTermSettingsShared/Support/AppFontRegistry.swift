import Observation

/// Resolves the user's selected UI font family to a concrete font name for
/// `AppTypography`. A dedicated `@Observable` class (rather than reading
/// `@Shared` directly inside `AppTypography`'s computed properties) so
/// SwiftUI's observation tracking of the ~123 call sites reading
/// `AppTypography.body` etc. is unambiguous, instead of relying on an
/// unverified "read `@Shared` inside a computed property evaluated during
/// `body`" edge case. Lives in `PTermSettingsShared` (not the app target)
/// so both `p-term` and `PTermSettingsFeature` can read it.
@MainActor
@Observable
public final class AppFontRegistry {
  public static let shared = AppFontRegistry()

  public private(set) var resolvedUIFontName: String?

  private init() {}

  public func refresh(from selection: AppFontSelection) {
    guard case .custom(let family) = selection, let name = FontFamilyResolver.regularFontName(forFamily: family) else {
      resolvedUIFontName = nil
      return
    }
    resolvedUIFontName = name
  }
}
