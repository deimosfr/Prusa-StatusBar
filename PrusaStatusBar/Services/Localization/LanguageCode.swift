import Foundation

/// Languages the user can pick for the in-app override. The raw value of every
/// non-`.system` case matches the on-disk `.lproj` directory name under
/// `PrusaStatusBar/Resources/`. To add a language, add a case here, ship the
/// matching `.lproj/Localizable.strings`, update `CFBundleLocalizations` in
/// `Info.plist` and `KNOWN_REGIONS` in `project.yml`.
/// See `LOCALIZATION.md` at the repo root for the full contributor recipe.
public enum LanguageCode: String, CaseIterable, Sendable, Identifiable, Hashable {
    case system = ""
    case en
    case de
    case fr
    case es
    case it
    case cs
    case pl
    case ptBR = "pt-BR"
    case ja
    case zhHans = "zh-Hans"

    public var id: String {
        rawValue
    }

    /// True when the case represents a real `.lproj` directory the app can
    /// load. The `.system` sentinel returns false; everything else true.
    public var isOverride: Bool {
        self != .system
    }

    /// Best-effort display name for use in the Picker. `.system` is rendered
    /// via the catalog key `general.language.system` and follows the current
    /// UI language. Every other case is rendered in its **own** locale
    /// (e.g. `fr` -> "Français", `ja` -> "日本語") so the user always sees
    /// each language by its native name regardless of the app's current
    /// language. Falls back to the raw code if Foundation cannot resolve.
    @MainActor
    public var displayName: String {
        switch self {
        case .system:
            return L10n.t("general.language.system")
        default:
            let locale = Locale(identifier: rawValue)
            let resolved = locale.localizedString(forIdentifier: rawValue)
            return resolved?.capitalized ?? rawValue
        }
    }
}
