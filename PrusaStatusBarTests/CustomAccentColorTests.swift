import Foundation
@testable import PrusaStatusBar
import SwiftUI
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Accent picker supports a custom color
///   (default hex on first launch, persistence round-trip).
/// - Hex parser correctness for `Theme.Palette.brand(.custom, customHex:)`.
struct CustomAccentColorTests {
    private func makePreferences() -> (UserPreferences, UserDefaults) {
        let suite = "PrusaStatusBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (UserPreferences(defaults: defaults), defaults)
    }

    @Test
    func customAccentHexDefaultsOnFirstLaunch() {
        let (prefs, _) = makePreferences()
        #expect(prefs.customAccentHex == UserPreferences.customAccentHexDefault)
    }

    @Test
    func customAccentHexRoundTripsThroughDefaults() {
        let (prefs, defaults) = makePreferences()
        prefs.customAccentHex = "#22AA88"
        #expect(prefs.customAccentHex == "#22AA88")
        let raw = defaults.string(forKey: UserPreferencesKey.customAccentColor)
        #expect(raw == "#22AA88")
    }

    @Test
    func customAccentHexBlankReadsAsDefault() {
        let (prefs, defaults) = makePreferences()
        defaults.set("   ", forKey: UserPreferencesKey.customAccentColor)
        #expect(prefs.customAccentHex == UserPreferences.customAccentHexDefault)
    }

    @Test
    func colorHexParsesCanonicalForm() {
        #expect(Color(hex: "#FF6B35") != nil)
        #expect(Color(hex: "FF6B35") != nil)
        #expect(Color(hex: "#000000") != nil)
        #expect(Color(hex: "#FFFFFF") != nil)
    }

    @Test
    func colorHexRejectsMalformedInput() {
        #expect(Color(hex: "") == nil)
        #expect(Color(hex: "#GG6B35") == nil)
        #expect(Color(hex: "#FF6B3") == nil)
        #expect(Color(hex: "#FF6B355") == nil)
        #expect(Color(hex: "#FFFFFFFF") == nil)
    }

    @Test
    func colorHexRoundTripsThroughToHex() {
        let original = "#22AA88"
        guard let parsed = Color(hex: original) else {
            Issue.record("Failed to parse known-good hex")
            return
        }
        #expect(parsed.toHex() == original)
    }
}
