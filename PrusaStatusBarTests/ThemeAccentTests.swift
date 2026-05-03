@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `accent-color-preference` Requirement: User can choose the brand accent
///   color (raw-value contract used to persist the selection).
struct ThemeAccentTests {
    @Test
    func accentRawValuesAreStable() {
        #expect(Theme.Accent.orange.rawValue == "orange")
        #expect(Theme.Accent.orangeLegacy.rawValue == "orange_legacy")
        #expect(Theme.Accent.green.rawValue == "green")
        #expect(Theme.Accent.custom.rawValue == "custom")
    }

    @Test
    func accentRoundTripsThroughRawValue() {
        #expect(Theme.Accent(rawValue: "orange") == .orange)
        #expect(Theme.Accent(rawValue: "orange_legacy") == .orangeLegacy)
        #expect(Theme.Accent(rawValue: "green") == .green)
        #expect(Theme.Accent(rawValue: "custom") == .custom)
        #expect(Theme.Accent(rawValue: "purple") == nil)
    }

    @Test
    func allCasesContainEveryAccent() {
        #expect(Set(Theme.Accent.allCases) == [.orange, .orangeLegacy, .green, .custom])
    }

    @Test
    func displayNamesMatchPrusaBranding() {
        #expect(Theme.Accent.orange.displayName == "Prusa Orange")
        #expect(Theme.Accent.orangeLegacy.displayName == "Old Prusa Orange")
        #expect(Theme.Accent.green.displayName == "Prusa Pro")
        #expect(Theme.Accent.custom.displayName == "Custom")
    }
}
