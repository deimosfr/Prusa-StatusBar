import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Printer tab edits Generic Camera
///   (framerate clamp on read, default values, round-trip set/get)
struct UserPreferencesGenericCameraTests {
    private func makePrefs() -> UserPreferences {
        let suite = "PrusaStatusBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserPreferences(defaults: defaults)
    }

    @Test
    func defaultsAreSensible() {
        let prefs = makePrefs()
        #expect(prefs.genericCameraEnabled == false)
        #expect(prefs.genericCameraStreamURL == nil)
        #expect(prefs.genericCameraStillImageURL == nil)
        #expect(prefs.genericCameraRTSPTransport == .tcp)
        #expect(prefs.genericCameraAuthMode == .none)
        #expect(prefs.genericCameraUsername == nil)
        #expect(prefs.genericCameraPasswordPlaintext == nil)
        #expect(prefs.genericCameraFramerate == UserPreferences.genericCameraFramerateDefault)
        #expect(prefs.genericCameraVerifySSL == true)
        #expect(prefs.genericCameraContentType == UserPreferences.genericCameraContentTypeDefault)
    }

    @Test
    func roundTripStrings() {
        let prefs = makePrefs()
        prefs.genericCameraStreamURL = "rtsp://cam/s"
        prefs.genericCameraStillImageURL = "https://cam/snap.jpg"
        prefs.genericCameraUsername = "admin"
        #expect(prefs.genericCameraStreamURL == "rtsp://cam/s")
        #expect(prefs.genericCameraStillImageURL == "https://cam/snap.jpg")
        #expect(prefs.genericCameraUsername == "admin")
    }

    @Test
    func emptyStringsClearURLs() {
        let prefs = makePrefs()
        prefs.genericCameraStreamURL = "rtsp://cam/s"
        prefs.genericCameraStreamURL = ""
        #expect(prefs.genericCameraStreamURL == nil)
    }

    @Test
    func framerateClampedHigh() {
        let prefs = makePrefs()
        prefs.genericCameraFramerate = 999
        #expect(prefs.genericCameraFramerate == UserPreferences.genericCameraFramerateMax)
    }

    @Test
    func framerateClampedLow() {
        let prefs = makePrefs()
        prefs.genericCameraFramerate = 0
        #expect(prefs.genericCameraFramerate == UserPreferences.genericCameraFramerateMin)
    }

    @Test
    func framerateClampedOnRawWrite() {
        let prefs = makePrefs()
        // Simulate a manual `defaults write` with an out-of-range value.
        prefs.defaultsAccess.set(99, forKey: UserPreferencesKey.genericCameraFramerate)
        #expect(prefs.genericCameraFramerate == UserPreferences.genericCameraFramerateMax)
    }

    @Test
    func authModeRoundTrip() {
        let prefs = makePrefs()
        prefs.genericCameraAuthMode = .digest
        #expect(prefs.genericCameraAuthMode == .digest)
        prefs.genericCameraAuthMode = .basic
        #expect(prefs.genericCameraAuthMode == .basic)
    }

    @Test
    func transportRoundTrip() {
        let prefs = makePrefs()
        prefs.genericCameraRTSPTransport = .udpMulticast
        #expect(prefs.genericCameraRTSPTransport == .udpMulticast)
    }

    @Test
    func contentTypeFallsBackToDefault() {
        let prefs = makePrefs()
        prefs.genericCameraContentType = "  "
        #expect(prefs.genericCameraContentType == UserPreferences.genericCameraContentTypeDefault)
    }

    @Test
    func verifySSLDefaultsOn() {
        let prefs = makePrefs()
        // Never written -> default ON.
        #expect(prefs.genericCameraVerifySSL == true)
        prefs.genericCameraVerifySSL = false
        #expect(prefs.genericCameraVerifySSL == false)
    }
}
