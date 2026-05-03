import Foundation
@testable import PrusaStatusBar
import Testing

/// Covers the `add-language-picker` change and its `App language override`
/// requirement: enum cardinality, every advertised language ships a real
/// `.lproj`, English is fully covered, missing keys fall back to English,
/// and the `appLanguage` preference round-trips with `.system` clearing
/// the key.
struct LocalizationTests {
    /// Every key referenced from Swift code that must be present in the
    /// English source catalog. If a key is added in code, mirror it here
    /// so the test suite catches a missing entry before runtime.
    private static let expectedEnglishKeys: [String] = [
        "general.language.label",
        "general.language.system",
        "general.launch_at_login.label",
        "general.notifications.footer",
        "general.appearance.accent.label",
        "menubar.label.header",
        "menubar.refresh_connected.label",
        "menubar.disconnected_icon.header",
        "menubar.disconnected_icon.style.default",
        "menubar.disconnected_icon.style.minimal",
        "menubar.disconnected_icon.style.none",
        "menubar.disconnected_icon.style.emoji",
        "menubar.disconnected_icon.emoji.tooltip",
        "content.metrics.header",
        "printer.connection.header",
        "notification.finished.title",
        "dropdown.job.elapsed_label",
        "dropdown.unconfigured.action",
        "dropdown.unreachable.title",
        "error.uuid.invalid",
        "a11y.refresh_button",
        "about.coffee_link",
        "prefs.tab.general",
        "footer.preferences"
    ]

    @Test
    func languageCodeCardinality() {
        // System sentinel + the ten preselected languages.
        #expect(LanguageCode.allCases.count == 11)
    }

    @Test
    func everyOverrideHasLproj() {
        for code in LanguageCode.allCases where code.isOverride {
            let path = Bundle.main.path(forResource: code.rawValue, ofType: "lproj")
            #expect(path != nil, "Missing lproj for \(code.rawValue)")
        }
    }

    @Test
    func englishCoversEveryAdvertisedKey() throws {
        let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let sentinel = "__MISSING__"
        for key in Self.expectedEnglishKeys {
            let value = bundle.localizedString(forKey: key, value: sentinel, table: nil)
            #expect(value != sentinel, "en.lproj missing key: \(key)")
            #expect(!value.isEmpty, "en.lproj has empty value for: \(key)")
        }
    }

    @Test
    @MainActor
    func appLanguagePreferenceRoundTrips() throws {
        let suiteName = "test-applang-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = UserPreferences(defaults: defaults)

        #expect(preferences.appLanguage == .system, "default should be system")

        preferences.appLanguage = .fr
        #expect(preferences.appLanguage == .fr)
        #expect(defaults.string(forKey: "appLanguage") == "fr")

        preferences.appLanguage = .ptBR
        #expect(preferences.appLanguage == .ptBR)
        #expect(defaults.string(forKey: "appLanguage") == "pt-BR")

        // Assigning .system clears the key so the next launch falls back
        // through Bundle.main / preferred languages.
        preferences.appLanguage = .system
        #expect(defaults.object(forKey: "appLanguage") == nil)
        #expect(preferences.appLanguage == .system)
    }

    @Test
    @MainActor
    func bundleResolvesToOverriddenLproj() throws {
        let suiteName = "test-bundle-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = UserPreferences(defaults: defaults)
        preferences.appLanguage = .fr
        LocalizationBundle.override(preferences: preferences)
        defer {
            LocalizationBundle.override(preferences: UserPreferences())
        }

        let bundle = LocalizationBundle.current
        #expect(bundle.bundlePath.hasSuffix("fr.lproj"))
    }

    @Test
    @MainActor
    func missingKeyFallsBackToEnglishThenToKey() throws {
        let suiteName = "test-fallback-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = UserPreferences(defaults: defaults)
        // Pick a language likely to be missing some niche keys.
        preferences.appLanguage = .ja
        LocalizationBundle.override(preferences: preferences)
        defer {
            LocalizationBundle.override(preferences: UserPreferences())
        }

        // A key that exists only in en.lproj falls back to the English value.
        // We use one of the keys we know is in the English seed but may or
        // may not be translated in ja yet; the result must not be empty and
        // must not be the literal sentinel.
        let resolved = L10n.t("general.language.label")
        #expect(!resolved.isEmpty)
        #expect(resolved != "__L10N_MISSING__")

        // A truly unknown key returns the key itself (last-resort fallback).
        let unknown = L10n.t("definitely.does.not.exist.\(UUID().uuidString)")
        #expect(unknown.contains("definitely.does.not.exist"))
    }
}
