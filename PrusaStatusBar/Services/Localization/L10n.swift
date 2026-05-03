import Foundation

/// Single entry point for localized strings. Every visible UI literal in the
/// app SHOULD be replaced with `L10n.t("some.key")`. Values live in
/// `PrusaStatusBar/Resources/<lang>.lproj/Localizable.strings`.
///
/// Lookup contract: the chosen-language bundle is consulted first, then the
/// English bundle as a fallback for keys that have not yet been translated,
/// then the raw key itself as a last resort. This means contributors can
/// translate keys at their own pace: a partially-translated `fr.lproj` shows
/// French where translated and English everywhere else, never an empty string.
@MainActor
public enum L10n {
    private static let missingSentinel = "__L10N_MISSING__"

    public static func t(_ key: String, comment _: String = "") -> String {
        let primary = LocalizationBundle.current
            .localizedString(forKey: key, value: missingSentinel, table: nil)
        if primary != missingSentinel {
            return primary
        }
        let fallback = LocalizationBundle.englishFallback
            .localizedString(forKey: key, value: missingSentinel, table: nil)
        if fallback != missingSentinel {
            return fallback
        }
        return key
    }

    /// Format-string variant for `%@` / `%lld` placeholders. Equivalent to
    /// `String(format: L10n.t(key), arguments)` but reads better at the call
    /// site. Falls through to the same fallback chain.
    public static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }
}

/// Resolves the `Bundle` to use for the next string lookup based on the
/// user-selected `LanguageCode`. Stays on the main actor because
/// `UserPreferences.appLanguage` is read from there and the cache is shared
/// across UI calls. `.system` returns `Bundle.main`, which makes Apple's
/// normal preferred-languages chain do its thing.
@MainActor
public enum LocalizationBundle {
    private static var cache: [String: Bundle] = [:]
    private static var preferences: UserPreferences = .init()

    /// Lets tests inject a custom `UserPreferences` (e.g. one backed by a
    /// throwaway `UserDefaults` suite) without polluting the user's real
    /// defaults. Production code never calls this.
    public static func override(preferences: UserPreferences) {
        self.preferences = preferences
        cache.removeAll()
    }

    public static var current: Bundle {
        let code = preferences.appLanguage
        guard code.isOverride else { return .main }
        return loadedBundle(for: code) ?? .main
    }

    /// English bundle, used as a per-key fallback when the chosen language is
    /// missing a translation. Always loaded from `en.lproj` if present;
    /// otherwise `Bundle.main` (which the app declares as English).
    public static var englishFallback: Bundle {
        loadedBundle(for: .en) ?? .main
    }

    private static func loadedBundle(for code: LanguageCode) -> Bundle? {
        if let cached = cache[code.rawValue] { return cached }
        guard
            let path = Bundle.main.path(forResource: code.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return nil
        }
        cache[code.rawValue] = bundle
        return bundle
    }
}
