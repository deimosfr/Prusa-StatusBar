import Foundation
@testable import PrusaStatusBar
import Testing

// Spec coverage:
// - `polling` Requirement: Background polling refreshes status on a
//   user-configurable interval (clamping behavior)
// - `menu-bar-ui` Requirement: General tab exposes refresh interval and
//   optional dropdown rows (defaults)
// swiftlint:disable:next type_body_length
struct UserPreferencesTests {
    private func makePreferences() -> (UserPreferences, UserDefaults) {
        let suite = "PrusaStatusBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (UserPreferences(defaults: defaults), defaults)
    }

    @Test
    func refreshIntervalDefaultsTo20WhenUnset() {
        let (prefs, _) = makePreferences()
        #expect(prefs.refreshIntervalSeconds == 20)
    }

    @Test
    func refreshIntervalRoundTripsInRange() {
        let (prefs, _) = makePreferences()
        prefs.refreshIntervalSeconds = 30
        #expect(prefs.refreshIntervalSeconds == 30)
    }

    @Test
    func refreshIntervalClampsBelowMinimum() {
        let (prefs, _) = makePreferences()
        prefs.refreshIntervalSeconds = 0
        #expect(prefs.refreshIntervalSeconds == UserPreferences.refreshIntervalMin)
    }

    @Test
    func refreshIntervalClampsAboveMaximum() {
        let (prefs, _) = makePreferences()
        prefs.refreshIntervalSeconds = 9999
        #expect(prefs.refreshIntervalSeconds == UserPreferences.refreshIntervalMax)
    }

    @Test
    func refreshIntervalCeilingIs600() {
        #expect(UserPreferences.refreshIntervalMax == 600)
    }

    @Test
    func disconnectedRefreshIntervalDefaultsTo300WhenUnset() {
        let (prefs, _) = makePreferences()
        #expect(prefs.disconnectedRefreshIntervalSeconds == 300)
    }

    @Test
    func disconnectedRefreshIntervalRoundTripsInRange() {
        let (prefs, _) = makePreferences()
        prefs.disconnectedRefreshIntervalSeconds = 300
        #expect(prefs.disconnectedRefreshIntervalSeconds == 300)
    }

    @Test
    func disconnectedRefreshIntervalClampsBelowMinimum() {
        let (prefs, _) = makePreferences()
        prefs.disconnectedRefreshIntervalSeconds = 0
        #expect(prefs.disconnectedRefreshIntervalSeconds == UserPreferences.disconnectedRefreshIntervalMin)
    }

    @Test
    func disconnectedRefreshIntervalClampsAboveMaximum() {
        let (prefs, _) = makePreferences()
        prefs.disconnectedRefreshIntervalSeconds = 99999
        #expect(prefs.disconnectedRefreshIntervalSeconds == UserPreferences.disconnectedRefreshIntervalMax)
    }

    @Test
    func disconnectedRefreshIntervalClampsOutOfRangeReadFromDefaults() {
        let (prefs, defaults) = makePreferences()
        defaults.set(1, forKey: UserPreferencesKey.disconnectedRefreshIntervalSeconds)
        #expect(prefs.disconnectedRefreshIntervalSeconds == UserPreferences.disconnectedRefreshIntervalMin)
    }

    @Test
    func refreshIntervalClampsOutOfRangeReadFromDefaults() {
        let (prefs, defaults) = makePreferences()
        // Simulate a manual `defaults write` that wrote a too-low value.
        defaults.set(0, forKey: UserPreferencesKey.refreshIntervalSeconds)
        #expect(prefs.refreshIntervalSeconds == UserPreferences.refreshIntervalMin)
    }

    @Test
    func optionalRowTogglesDefaultOff() {
        let (prefs, _) = makePreferences()
        #expect(prefs.showSpeed == false)
        #expect(prefs.showZHeight == false)
        #expect(prefs.showNozzleDiameter == false)
    }

    @Test
    func optionalRowTogglesRoundTrip() {
        let (prefs, _) = makePreferences()
        prefs.showSpeed = true
        prefs.showZHeight = true
        prefs.showNozzleDiameter = true
        #expect(prefs.showSpeed)
        #expect(prefs.showZHeight)
        #expect(prefs.showNozzleDiameter)
    }

    @Test
    func configuredNozzleDiametersDefaultToAutomatic() {
        let (prefs, _) = makePreferences()
        #expect(prefs.configuredNozzleDiameters.isEmpty)
    }

    @Test
    func configuredNozzleDiametersRoundTripAndClamp() {
        let (prefs, _) = makePreferences()
        prefs.configuredNozzleDiameters = [0.05, 0.6, 2.0, 0.25, 0.4, 0.8, 0.15, 0.5, 1.0]
        #expect(prefs.configuredNozzleDiameters == [0.1, 0.6, 1.8, 0.25, 0.4, 0.8, 0.15, 0.5])
        prefs.configuredNozzleDiameters = []
        #expect(prefs.configuredNozzleDiameters.isEmpty)
    }

    @MainActor
    @Test
    func configuredNozzlesOverridePrusaLinkDiameter() {
        let model = AppModel()
        model.printerInfo = PrinterInfo(nozzleDiameter: 0.6)
        #expect(model.effectiveNozzleDiameters == [0.6])
        model.configuredNozzleDiameters = [0.6, 0.4]
        #expect(model.effectiveNozzleDiameters == [0.6, 0.4])
    }

    @Test
    func prusaConnectUUIDIsNilWhenUnset() {
        let (prefs, _) = makePreferences()
        #expect(prefs.prusaConnectUUID == nil)
    }

    @Test
    func prusaConnectUUIDRoundTrips() {
        let (prefs, _) = makePreferences()
        prefs.prusaConnectUUID = "199c3848-d807-437e-ad78-4d1b2519c463"
        #expect(prefs.prusaConnectUUID == "199c3848-d807-437e-ad78-4d1b2519c463")
        prefs.prusaConnectUUID = nil
        #expect(prefs.prusaConnectUUID == nil)
    }

    @Test
    func rtspURLIsNilWhenUnset() {
        let (prefs, _) = makePreferences()
        #expect(prefs.rtspURL == nil)
    }

    @Test
    func rtspURLRoundTrips() {
        let (prefs, _) = makePreferences()
        prefs.rtspURL = "rtsp://192.168.94.109:554/live/"
        #expect(prefs.rtspURL == "rtsp://192.168.94.109:554/live/")
        prefs.rtspURL = nil
        #expect(prefs.rtspURL == nil)
    }

    @Test
    func accentDefaultsToOrange() {
        let (prefs, _) = makePreferences()
        #expect(prefs.accent == .orange)
    }

    @Test
    func accentRoundTrips() {
        let (prefs, _) = makePreferences()
        prefs.accent = .green
        #expect(prefs.accent == .green)
        prefs.accent = .orangeLegacy
        #expect(prefs.accent == .orangeLegacy)
        prefs.accent = .orange
        #expect(prefs.accent == .orange)
    }

    @Test
    func accentFallsBackToOrangeOnUnknownStoredValue() {
        let (prefs, defaults) = makePreferences()
        defaults.set("turquoise", forKey: UserPreferencesKey.accentColor)
        #expect(prefs.accent == .orange)
    }

    @Test
    func useKeychainForApiKeyDefaultsToOn() {
        let (prefs, _) = makePreferences()
        #expect(prefs.useKeychainForApiKey == true)
    }

    @Test
    func useKeychainForApiKeyRoundTrips() {
        let (prefs, _) = makePreferences()
        prefs.useKeychainForApiKey = false
        #expect(prefs.useKeychainForApiKey == false)
        prefs.useKeychainForApiKey = true
        #expect(prefs.useKeychainForApiKey == true)
    }

    @Test
    func printerApiKeyPlaintextIsNilWhenUnset() {
        let (prefs, _) = makePreferences()
        #expect(prefs.printerApiKeyPlaintext == nil)
    }

    @Test
    func printerApiKeyPlaintextRoundTrips() {
        let (prefs, _) = makePreferences()
        prefs.printerApiKeyPlaintext = "abc123"
        #expect(prefs.printerApiKeyPlaintext == "abc123")
        prefs.printerApiKeyPlaintext = nil
        #expect(prefs.printerApiKeyPlaintext == nil)
    }

    @Test
    func buddyCameraEnabledDefaultsToOff() {
        let (prefs, _) = makePreferences()
        #expect(prefs.buddyCameraEnabled == false)
    }

    @Test
    func buddyCameraEnabledRoundTrips() {
        let (prefs, _) = makePreferences()
        prefs.buddyCameraEnabled = true
        #expect(prefs.buddyCameraEnabled == true)
        prefs.buddyCameraEnabled = false
        #expect(prefs.buddyCameraEnabled == false)
    }

    @Test
    func printerNameOverrideIsNilWhenUnset() {
        let (prefs, _) = makePreferences()
        #expect(prefs.printerNameOverride == nil)
    }

    @Test
    func printerNameOverrideRoundTripsTrimmed() {
        let (prefs, _) = makePreferences()
        prefs.printerNameOverride = "  Lab MK4  "
        #expect(prefs.printerNameOverride == "Lab MK4")
    }

    @Test
    func printerNameOverrideEmptyStringNormalisesToNil() {
        let (prefs, _) = makePreferences()
        prefs.printerNameOverride = "Office"
        prefs.printerNameOverride = ""
        #expect(prefs.printerNameOverride == nil)
    }

    @Test
    func printerNameOverrideWhitespaceOnlyReadsAsNil() {
        let (prefs, defaults) = makePreferences()
        defaults.set("   \n\t  ", forKey: UserPreferencesKey.printerNameOverride)
        #expect(prefs.printerNameOverride == nil)
    }

    @Test
    func showRemainingTimeDefaultsToOn() {
        let (prefs, _) = makePreferences()
        #expect(prefs.showRemainingTime == true)
    }

    @Test
    func showRemainingTimeRoundTrips() {
        let (prefs, _) = makePreferences()
        prefs.showRemainingTime = false
        #expect(prefs.showRemainingTime == false)
        prefs.showRemainingTime = true
        #expect(prefs.showRemainingTime == true)
    }

    @Test
    func showRemainingTimeMigratesFromLegacyHideKey() {
        let (prefs, defaults) = makePreferences()
        defaults.set(true, forKey: UserPreferencesKey.hideRemainingTime)
        #expect(prefs.showRemainingTime == false)
        // Legacy key consumed.
        #expect(defaults.object(forKey: UserPreferencesKey.hideRemainingTime) == nil)
        // Migration result persisted under the new key.
        #expect(defaults.object(forKey: UserPreferencesKey.showRemainingTime) != nil)
        // Subsequent reads do not re-trigger the migration path.
        #expect(prefs.showRemainingTime == false)
    }

    @Test
    func showRemainingTimeMigrationDoesNotOverridePositiveSetting() {
        let (prefs, defaults) = makePreferences()
        prefs.showRemainingTime = false
        // A stray legacy key should be ignored once the new key is set.
        defaults.set(false, forKey: UserPreferencesKey.hideRemainingTime)
        #expect(prefs.showRemainingTime == false)
    }

    @Test
    func showPercentageDefaultsToOn() {
        let (prefs, _) = makePreferences()
        #expect(prefs.showPercentage == true)
    }

    @Test
    func showPercentageRoundTrips() {
        let (prefs, _) = makePreferences()
        prefs.showPercentage = false
        #expect(prefs.showPercentage == false)
        prefs.showPercentage = true
        #expect(prefs.showPercentage == true)
    }

    @Test
    func showTemperaturesDefaultOnAndRoundTrip() {
        let (prefs, _) = makePreferences()
        #expect(prefs.showTemperatures == true)
        prefs.showTemperatures = false
        #expect(prefs.showTemperatures == false)
        prefs.showTemperatures = true
        #expect(prefs.showTemperatures == true)
    }

    @Test
    func showJobActionsDefaultOnAndRoundTrip() {
        let (prefs, _) = makePreferences()
        #expect(prefs.showJobActions == true)
        prefs.showJobActions = false
        #expect(prefs.showJobActions == false)
        prefs.showJobActions = true
        #expect(prefs.showJobActions == true)
    }

    @Test
    func showPrusaLinkButtonDefaultOnAndRoundTrip() {
        let (prefs, _) = makePreferences()
        #expect(prefs.showPrusaLinkButton == true)
        prefs.showPrusaLinkButton = false
        #expect(prefs.showPrusaLinkButton == false)
        prefs.showPrusaLinkButton = true
        #expect(prefs.showPrusaLinkButton == true)
    }

    @Test
    func showPrusaConnectButtonDefaultOnAndRoundTrip() {
        let (prefs, _) = makePreferences()
        #expect(prefs.showPrusaConnectButton == true)
        prefs.showPrusaConnectButton = false
        #expect(prefs.showPrusaConnectButton == false)
        prefs.showPrusaConnectButton = true
        #expect(prefs.showPrusaConnectButton == true)
    }

    @Test
    func printerBaseURLSecondaryIsNilWhenUnset() {
        let (prefs, _) = makePreferences()
        #expect(prefs.printerBaseURLSecondary == nil)
    }

    @Test
    func printerBaseURLSecondaryRoundTripsTrimmed() {
        let (prefs, _) = makePreferences()
        prefs.printerBaseURLSecondary = "  http://printer.vpn  "
        #expect(prefs.printerBaseURLSecondary == "http://printer.vpn")
    }

    @Test
    func printerBaseURLSecondaryEmptyStringNormalisesToNil() {
        let (prefs, defaults) = makePreferences()
        prefs.printerBaseURLSecondary = "http://printer.vpn"
        prefs.printerBaseURLSecondary = ""
        #expect(prefs.printerBaseURLSecondary == nil)
        #expect(defaults.object(forKey: UserPreferencesKey.printerBaseURLSecondary) == nil)
    }

    @Test
    func printerBaseURLSecondaryWhitespaceOnlyReadsAsNil() {
        let (prefs, defaults) = makePreferences()
        defaults.set("   \n\t  ", forKey: UserPreferencesKey.printerBaseURLSecondary)
        #expect(prefs.printerBaseURLSecondary == nil)
    }
}
