import Foundation

/// Stable keys for the small set of preferences kept in `UserDefaults`.
/// The API key is NOT here, it lives in the Keychain.
enum UserPreferencesKey {
    static let printerBaseURL = "printerBaseURL"
    static let printerBaseURLSecondary = "printerBaseURLSecondary"
    static let notificationsEnabled = "notificationsEnabled"
    static let notifyOnStarted = "notifyOnStarted"
    static let notifyOnFinished = "notifyOnFinished"
    static let notifyOnAttention = "notifyOnAttention"
    static let notifyOnError = "notifyOnError"
    static let launchAtLogin = "launchAtLogin"
    static let hideRemainingTime = "hideRemainingTime"
    static let showRemainingTime = "showRemainingTime"
    static let showPercentage = "showPercentage"
    static let refreshIntervalSeconds = "refreshIntervalSeconds"
    static let disconnectedRefreshIntervalSeconds = "disconnectedRefreshIntervalSeconds"
    static let showSpeed = "showSpeed"
    static let showZHeight = "showZHeight"
    static let showNozzleDiameter = "showNozzleDiameter"
    static let showFilamentType = "showFilamentType"
    static let showMMU = "showMMU"
    static let showTemperatures = "showTemperatures"
    static let prusaConnectUUID = "prusaConnectUUID"
    static let rtspURL = "rtspURL"
    static let accentColor = "accentColor"
    static let customAccentColor = "customAccentColor"
    static let useKeychainForApiKey = "useKeychainForApiKey"
    static let printerApiKeyPlaintext = "printerApiKeyPlaintext"
    static let buddyCameraEnabled = "buddyCameraEnabled"
    static let printerNameOverride = "printerNameOverride"
    static let printerModel = "printerModel"
    static let progressBarStyle = "progressBarStyle"
    static let showJobActions = "showJobActions"
    static let showPrusaLinkButton = "showPrusaLinkButton"
    static let showPrusaConnectButton = "showPrusaConnectButton"
    static let appLanguage = "appLanguage"
    static let disconnectedIconStyle = "disconnectedIconStyle"
    static let disconnectedIconEmoji = "disconnectedIconEmoji"
    static let customActionsPublicJSON = "customActionsPublicJSON"
    static let recentSymbols = "recentSymbols"
    static let genericCameraEnabled = "genericCameraEnabled"
    static let genericCameraStillImageURL = "genericCameraStillImageURL"
    static let genericCameraStreamURL = "genericCameraStreamURL"
    static let genericCameraRTSPTransport = "genericCameraRTSPTransport"
    static let genericCameraAuthMode = "genericCameraAuthMode"
    static let genericCameraUsername = "genericCameraUsername"
    static let genericCameraPasswordPlaintext = "genericCameraPasswordPlaintext"
    static let genericCameraFramerate = "genericCameraFramerate"
    static let genericCameraVerifySSL = "genericCameraVerifySSL"
    static let genericCameraContentType = "genericCameraContentType"
    static func customActionSecretPlaintext(slot: CustomActionSlot) -> String {
        "customActionSecretPlaintext.\(slot.rawValue)"
    }
}

/// Visual style of the menu-bar icon while the printer is in the disconnected
/// state. `default` keeps the bundled `IconDisconnected` asset; `minimal`
/// shrinks it to a tiny clickable dot; `emoji` renders a user-chosen emoji.
public enum DisconnectedIconStyle: String, CaseIterable, Sendable {
    case `default`
    case minimal
    case none
    case emoji
}

/// Visual style of the print-job progress bar in the dropdown.
/// `premium` is the original gradient-capsule + sheen + glowing-dot design;
/// `spool` swaps the leading-edge dot for the Prusa filament spool wheel.
public enum ProgressBarStyle: String, CaseIterable, Sendable {
    case premium
    case spool
}

/// Lightweight typed accessor over `UserDefaults`. Exists so tests can inject a
/// fresh suite without touching the user's real defaults.
///
/// Named `UserPreferences` rather than `Settings` to avoid colliding with
/// SwiftUI's `Settings` scene type, declaring both in the same module makes
/// the scene initialiser ambiguous at the call site.
public final class UserPreferences: @unchecked Sendable {
    public static let refreshIntervalDefault = 20
    public static let refreshIntervalMin = 2
    public static let refreshIntervalMax = 600

    public static let disconnectedRefreshIntervalDefault = 300
    public static let disconnectedRefreshIntervalMin = 5
    public static let disconnectedRefreshIntervalMax = 3600

    private let defaults: UserDefaults

    /// Module-internal hatch so extension files (e.g.
    /// `UserPreferences+CustomActions.swift`) can read and write the
    /// underlying `UserDefaults` without being declared in this file.
    /// Kept `internal` so external consumers still go through the typed
    /// accessors above.
    var defaultsAccess: UserDefaults {
        defaults
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var printerBaseURL: String? {
        get { defaults.string(forKey: UserPreferencesKey.printerBaseURL) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.printerBaseURL) }
    }

    /// Optional secondary base URL used as a transparent fallback when the
    /// primary URL is unreachable (e.g. WireGuard / VPN path to the same
    /// printer). Empty or whitespace-only input is normalised to nil.
    public var printerBaseURLSecondary: String? {
        get {
            guard let raw = defaults.string(forKey: UserPreferencesKey.printerBaseURLSecondary) else {
                return nil
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        set {
            let normalised = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalised, !normalised.isEmpty {
                defaults.set(normalised, forKey: UserPreferencesKey.printerBaseURLSecondary)
            } else {
                defaults.removeObject(forKey: UserPreferencesKey.printerBaseURLSecondary)
            }
        }
    }

    public var notificationsEnabled: Bool {
        get {
            // Default ON if the user has never set it.
            if defaults.object(forKey: UserPreferencesKey.notificationsEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: UserPreferencesKey.notificationsEnabled)
        }
        set { defaults.set(newValue, forKey: UserPreferencesKey.notificationsEnabled) }
    }

    public var notifyOnFinished: Bool {
        get { boolDefaultingOn(UserPreferencesKey.notifyOnFinished) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.notifyOnFinished) }
    }

    public var notifyOnAttention: Bool {
        get { boolDefaultingOn(UserPreferencesKey.notifyOnAttention) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.notifyOnAttention) }
    }

    public var notifyOnError: Bool {
        get { boolDefaultingOn(UserPreferencesKey.notifyOnError) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.notifyOnError) }
    }

    /// Read a `Bool` preference that should default to ON when the key has
    /// never been written. `defaults.bool(forKey:)` returns `false` for missing
    /// keys, which silently turns into a regression for users upgrading from
    /// a version where the per-state toggle did not exist.
    private func boolDefaultingOn(_ key: String) -> Bool {
        if defaults.object(forKey: key) == nil {
            return true
        }
        return defaults.bool(forKey: key)
    }

    /// Controls whether the menu-bar label includes the compact remaining-time
    /// segment (e.g. `"9h32m"`) and whether the JobCard surfaces remaining
    /// time and ETA. Defaults ON. On first read, a legacy `hideRemainingTime`
    /// key (the previous, negatively-phrased toggle) is consumed so existing
    /// users keep their setting.
    public var showRemainingTime: Bool {
        get {
            if defaults.object(forKey: UserPreferencesKey.showRemainingTime) == nil {
                if defaults.object(forKey: UserPreferencesKey.hideRemainingTime) != nil {
                    let migrated = !defaults.bool(forKey: UserPreferencesKey.hideRemainingTime)
                    defaults.set(migrated, forKey: UserPreferencesKey.showRemainingTime)
                    defaults.removeObject(forKey: UserPreferencesKey.hideRemainingTime)
                    return migrated
                }
                return true
            }
            return defaults.bool(forKey: UserPreferencesKey.showRemainingTime)
        }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showRemainingTime) }
    }

    /// Controls whether the menu-bar label includes the integer-percent
    /// segment (e.g. `"62%"`). Defaults ON. Does not affect the dropdown,
    /// where the progress bar already conveys percent.
    public var showPercentage: Bool {
        get {
            if defaults.object(forKey: UserPreferencesKey.showPercentage) == nil {
                return true
            }
            return defaults.bool(forKey: UserPreferencesKey.showPercentage)
        }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showPercentage) }
    }

    /// User-configurable polling interval used while the printer is reachable,
    /// in seconds. Default 10 s, clamped to the closed range [2, 600] on read
    /// so that a manual `defaults write` with an out-of-range value does not
    /// hammer the printer or stall the UI.
    public var refreshIntervalSeconds: Int {
        get {
            if defaults.object(forKey: UserPreferencesKey.refreshIntervalSeconds) == nil {
                return Self.refreshIntervalDefault
            }
            let raw = defaults.integer(forKey: UserPreferencesKey.refreshIntervalSeconds)
            return max(Self.refreshIntervalMin, min(Self.refreshIntervalMax, raw))
        }
        set {
            let clamped = max(Self.refreshIntervalMin, min(Self.refreshIntervalMax, newValue))
            defaults.set(clamped, forKey: UserPreferencesKey.refreshIntervalSeconds)
        }
    }

    /// User-configurable polling interval used while the printer is
    /// disconnected (>= 2 consecutive `.unreachable` failures). Default 60 s,
    /// clamped to the closed range [5, 3600]. Kept independent of the
    /// connected interval so users can hammer a flaky link or back off on a
    /// printer that is just powered down.
    public var disconnectedRefreshIntervalSeconds: Int {
        get {
            if defaults.object(forKey: UserPreferencesKey.disconnectedRefreshIntervalSeconds) == nil {
                return Self.disconnectedRefreshIntervalDefault
            }
            let raw = defaults.integer(forKey: UserPreferencesKey.disconnectedRefreshIntervalSeconds)
            return max(Self.disconnectedRefreshIntervalMin, min(Self.disconnectedRefreshIntervalMax, raw))
        }
        set {
            let clamped = max(Self.disconnectedRefreshIntervalMin, min(Self.disconnectedRefreshIntervalMax, newValue))
            defaults.set(clamped, forKey: UserPreferencesKey.disconnectedRefreshIntervalSeconds)
        }
    }

    public var showSpeed: Bool {
        get { defaults.bool(forKey: UserPreferencesKey.showSpeed) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showSpeed) }
    }

    public var showZHeight: Bool {
        get { defaults.bool(forKey: UserPreferencesKey.showZHeight) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showZHeight) }
    }

    public var showNozzleDiameter: Bool {
        get { defaults.bool(forKey: UserPreferencesKey.showNozzleDiameter) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showNozzleDiameter) }
    }

    /// Filament info is useful even on non-MMU printers (sanity-check the
    /// loaded spool without walking to the printer), so this defaults ON
    /// unlike the other additional-info toggles. Users who do not want it
    /// can disable in Preferences > Menu Content.
    public var showFilamentType: Bool {
        get { boolDefaultingOn(UserPreferencesKey.showFilamentType) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showFilamentType) }
    }

    public var showMMU: Bool {
        get { defaults.bool(forKey: UserPreferencesKey.showMMU) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showMMU) }
    }

    /// Master toggle for the dropdown's nozzle + bed `TempCard` row.
    /// Defaults ON so existing users see no behavior change on upgrade; off
    /// hides both heaters regardless of reported values.
    public var showTemperatures: Bool {
        get { boolDefaultingOn(UserPreferencesKey.showTemperatures) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showTemperatures) }
    }

    /// Master toggle for the dropdown's Job Actions section (Resume /
    /// Pause / Stop). Defaults ON so a fresh install surfaces the controls.
    public var showJobActions: Bool {
        get { boolDefaultingOn(UserPreferencesKey.showJobActions) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showJobActions) }
    }

    /// Visibility toggle for the dropdown's PrusaLink button in LinksRow.
    /// Defaults ON so existing users see no behavior change on upgrade.
    /// Symmetric with `showPrusaConnectButton`.
    public var showPrusaLinkButton: Bool {
        get { boolDefaultingOn(UserPreferencesKey.showPrusaLinkButton) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showPrusaLinkButton) }
    }

    /// Visibility toggle for the dropdown's PrusaConnect button in LinksRow.
    /// Defaults ON. When ON, an empty `prusaConnectUUID` falls back to the
    /// generic cloud dashboard at `https://connect.prusa3d.com`; a populated
    /// UUID deep-links to `https://connect.prusa3d.com/printer/{uuid}/dashboard`.
    public var showPrusaConnectButton: Bool {
        get { boolDefaultingOn(UserPreferencesKey.showPrusaConnectButton) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.showPrusaConnectButton) }
    }

    public var prusaConnectUUID: String? {
        get { defaults.string(forKey: UserPreferencesKey.prusaConnectUUID) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.prusaConnectUUID) }
    }

    public var rtspURL: String? {
        get { defaults.string(forKey: UserPreferencesKey.rtspURL) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.rtspURL) }
    }

    /// Optional user-supplied display name that takes precedence over the
    /// printer name returned by `/api/v1/info` when rendering the dropdown
    /// title. Whitespace-only and empty values normalise to nil on read so a
    /// blanked-out field does not lock the UI to an empty title.
    public var printerNameOverride: String? {
        get {
            guard let raw = defaults.string(forKey: UserPreferencesKey.printerNameOverride) else {
                return nil
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        set {
            let normalised = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalised, !normalised.isEmpty {
                defaults.set(normalised, forKey: UserPreferencesKey.printerNameOverride)
            } else {
                defaults.removeObject(forKey: UserPreferencesKey.printerNameOverride)
            }
        }
    }

    /// The illustration selected for offline and loading printer cards.
    /// Existing installations keep the former CORE One illustration.
    public var printerModel: PrinterModel {
        get {
            guard let raw = defaults.string(forKey: UserPreferencesKey.printerModel),
                  let model = PrinterModel(rawValue: raw)
            else {
                return .coreOne
            }
            return model
        }
        set { defaults.set(newValue.rawValue, forKey: UserPreferencesKey.printerModel) }
    }

    /// Master toggle for the Buddy Camera feature. Defaults to OFF so the
    /// dropdown stays slim until the user opts in. The host (`rtspURL`)
    /// remains persisted independently so flipping the toggle does not
    /// destroy the user's typed value.
    public var buddyCameraEnabled: Bool {
        get { defaults.bool(forKey: UserPreferencesKey.buddyCameraEnabled) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.buddyCameraEnabled) }
    }

    /// Toggle controlling where the PrusaLink API key is stored. ON (default)
    /// routes through the macOS Keychain; OFF persists to
    /// `printerApiKeyPlaintext` in this `UserDefaults` suite. Flipping the
    /// toggle in Preferences triggers a migration in `ApiKeyStore`.
    public var useKeychainForApiKey: Bool {
        get {
            if defaults.object(forKey: UserPreferencesKey.useKeychainForApiKey) == nil {
                return true
            }
            return defaults.bool(forKey: UserPreferencesKey.useKeychainForApiKey)
        }
        set { defaults.set(newValue, forKey: UserPreferencesKey.useKeychainForApiKey) }
    }

    /// Plain-text fallback slot for the API key, used only when
    /// `useKeychainForApiKey == false`. The Keychain remains the default; this
    /// slot is kept `nil` whenever the toggle is ON.
    public var printerApiKeyPlaintext: String? {
        get { defaults.string(forKey: UserPreferencesKey.printerApiKeyPlaintext) }
        set { defaults.set(newValue, forKey: UserPreferencesKey.printerApiKeyPlaintext) }
    }

    /// Brand accent color: orange (default), legacy orange, green, or a user
    /// chosen custom color. Persisted as the raw string of `Theme.Accent` so a
    /// user-edited `defaults write` round-trips.
    public var accent: Theme.Accent {
        get {
            guard let raw = defaults.string(forKey: UserPreferencesKey.accentColor),
                  let value = Theme.Accent(rawValue: raw)
            else {
                return .orange
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: UserPreferencesKey.accentColor) }
    }

    /// Default `#RRGGBB` value used for the custom-accent slot on first
    /// launch. Distinct from any of the three Prusa presets so users can see
    /// the slot is active when they first scrub through it.
    public static let customAccentHexDefault = "#FF6B35"

    /// Custom-accent hex string consulted when `accent == .custom`. Stored as
    /// `#RRGGBB` so a user-edited `defaults write` round-trips. Empty / blank
    /// values fall back to `customAccentHexDefault` so the picker never reads
    /// an invalid color.
    public var customAccentHex: String {
        get {
            let raw = defaults.string(forKey: UserPreferencesKey.customAccentColor) ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? Self.customAccentHexDefault : trimmed
        }
        set { defaults.set(newValue, forKey: UserPreferencesKey.customAccentColor) }
    }

    /// User-selected app language. Defaults to `.system` which clears the
    /// preference and lets `Bundle.main` resolve through the macOS preferred
    /// languages list. Unknown raw values fall back to `.system`. Assigning
    /// `.system` removes the key so the preference round-trips cleanly.
    public var appLanguage: LanguageCode {
        get {
            guard let raw = defaults.string(forKey: UserPreferencesKey.appLanguage),
                  let value = LanguageCode(rawValue: raw)
            else {
                return .system
            }
            return value
        }
        set {
            if newValue == .system {
                defaults.removeObject(forKey: UserPreferencesKey.appLanguage)
            } else {
                defaults.set(newValue.rawValue, forKey: UserPreferencesKey.appLanguage)
            }
        }
    }

    public static let disconnectedIconEmojiDefault = "\u{274C}"
}
