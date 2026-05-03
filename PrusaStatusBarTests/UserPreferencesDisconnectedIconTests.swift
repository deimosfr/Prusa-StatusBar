import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Disconnected icon is user-configurable
///   (default scenario, persistence scenario, emoji trimming + fallback)
struct UserPreferencesDisconnectedIconTests {
    private func makePreferences() -> (UserPreferences, UserDefaults) {
        let suite = "PrusaStatusBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (UserPreferences(defaults: defaults), defaults)
    }

    @Test
    func defaultsToDefaultWhenUnset() {
        let (prefs, _) = makePreferences()
        #expect(prefs.disconnectedIconStyle == .default)
    }

    @Test
    func roundTripsMinimal() {
        let (prefs, _) = makePreferences()
        prefs.disconnectedIconStyle = .minimal
        #expect(prefs.disconnectedIconStyle == .minimal)
    }

    @Test
    func roundTripsNone() {
        let (prefs, _) = makePreferences()
        prefs.disconnectedIconStyle = .none
        #expect(prefs.disconnectedIconStyle == .none)
    }

    @Test
    func roundTripsEmoji() {
        let (prefs, _) = makePreferences()
        prefs.disconnectedIconStyle = .emoji
        #expect(prefs.disconnectedIconStyle == .emoji)
    }

    @Test
    func unknownRawFallsBackToDefault() {
        let (prefs, defaults) = makePreferences()
        defaults.set("rainbow", forKey: UserPreferencesKey.disconnectedIconStyle)
        #expect(prefs.disconnectedIconStyle == .default)
    }

    @Test
    func setterPersistsRawString() {
        let (prefs, defaults) = makePreferences()
        prefs.disconnectedIconStyle = .emoji
        #expect(defaults.string(forKey: UserPreferencesKey.disconnectedIconStyle) == "emoji")
    }

    @Test
    func emojiDefaultsToCrossMark() {
        let (prefs, _) = makePreferences()
        #expect(prefs.disconnectedIconEmoji == "\u{274C}")
    }

    @Test
    func emojiRoundTrips() {
        let (prefs, _) = makePreferences()
        prefs.disconnectedIconEmoji = "💤"
        #expect(prefs.disconnectedIconEmoji == "💤")
    }

    @Test
    func emojiTrimsWhitespaceOnRead() {
        let (prefs, defaults) = makePreferences()
        defaults.set("  🛑  ", forKey: UserPreferencesKey.disconnectedIconEmoji)
        #expect(prefs.disconnectedIconEmoji == "🛑")
    }

    @Test
    func emojiBlankWriteRemovesKeyAndFallsBackToDefault() {
        let (prefs, defaults) = makePreferences()
        prefs.disconnectedIconEmoji = "💤"
        prefs.disconnectedIconEmoji = "   "
        #expect(defaults.object(forKey: UserPreferencesKey.disconnectedIconEmoji) == nil)
        #expect(prefs.disconnectedIconEmoji == "\u{274C}")
    }
}
