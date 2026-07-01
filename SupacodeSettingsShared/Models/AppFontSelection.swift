/// User-customizable font family for the app UI or the terminal.
/// `.systemDefault` serializes as `"system"`; `.custom(familyName)` carries the
/// raw NSFontManager family name. Unlike `RepositoryColor`, decode never fails —
/// an unrecognized string is treated as a candidate family name, since whether
/// that family is actually installed right now is a runtime concern
/// (`FontFamilyResolver.isInstalled`), not a decode-time one.
public nonisolated enum AppFontSelection: Hashable, Sendable, Codable {
  case systemDefault
  case custom(familyName: String)

  /// Wire format: `"system"` / the raw font family name.
  public var rawValue: String {
    switch self {
    case .systemDefault: "system"
    case .custom(let familyName): familyName
    }
  }

  /// Empty or `"system"` → `.systemDefault`; anything else is a candidate family name.
  public static func parse(_ rawValue: String) -> AppFontSelection {
    rawValue.isEmpty || rawValue == "system" ? .systemDefault : .custom(familyName: rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.parse(try container.decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// `true` for `.custom`; lets callers avoid spelling out the case path.
  public var isCustom: Bool {
    if case .custom = self { return true }
    return false
  }

  /// The selected family name, or `nil` for `.systemDefault`.
  public var familyName: String? {
    if case .custom(let familyName) = self { return familyName }
    return nil
  }
}
