import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Progress bar style is user-selectable
///   (default scenario, persistence scenario, unknown-stored-value scenario)
struct UserPreferencesProgressBarStyleTests {
    private func makePreferences() -> (UserPreferences, UserDefaults) {
        let suite = "PrusaStatusBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (UserPreferences(defaults: defaults), defaults)
    }

    @Test
    func defaultsToSpoolWhenUnset() {
        let (prefs, _) = makePreferences()
        #expect(prefs.progressBarStyle == .spool)
    }

    @Test
    func roundTripsPremium() {
        let (prefs, _) = makePreferences()
        prefs.progressBarStyle = .premium
        #expect(prefs.progressBarStyle == .premium)
    }

    @Test
    func roundTripsSpool() {
        let (prefs, _) = makePreferences()
        prefs.progressBarStyle = .spool
        #expect(prefs.progressBarStyle == .spool)
    }

    @Test
    func unknownRawFallsBackToSpool() {
        let (prefs, defaults) = makePreferences()
        defaults.set("rainbow", forKey: UserPreferencesKey.progressBarStyle)
        #expect(prefs.progressBarStyle == .spool)
    }

    @Test
    func setterPersistsRawString() {
        let (prefs, defaults) = makePreferences()
        prefs.progressBarStyle = .spool
        #expect(defaults.string(forKey: UserPreferencesKey.progressBarStyle) == "spool")
    }
}
