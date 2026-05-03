import Foundation

extension UserPreferencesKey {
    static let lastUpdateCheckDate = "lastUpdateCheckDate"
    static let latestUpdateTag = "latestUpdateTag"
    static let latestUpdateURL = "latestUpdateURL"
    static let checkForUpdatesEnabled = "checkForUpdatesEnabled"
}

public extension UserPreferences {
    /// Master toggle for the once-per-24h GitHub Releases check. Defaults
    /// ON so existing users get update notifications without opting in.
    /// When OFF, `UpdateChecker` skips network requests and the
    /// FooterBar callout is hidden.
    var checkForUpdatesEnabled: Bool {
        get {
            if defaultsAccess.object(forKey: UserPreferencesKey.checkForUpdatesEnabled) == nil {
                return true
            }
            return defaultsAccess.bool(forKey: UserPreferencesKey.checkForUpdatesEnabled)
        }
        set { defaultsAccess.set(newValue, forKey: UserPreferencesKey.checkForUpdatesEnabled) }
    }

    /// Timestamp of the most recent successful GitHub Releases check.
    /// Stored so quitting and relaunching within 24 hours does not trigger
    /// a fresh network request. Setting `nil` clears the key, which forces
    /// the next launch to check immediately.
    var lastUpdateCheckDate: Date? {
        get { defaultsAccess.object(forKey: UserPreferencesKey.lastUpdateCheckDate) as? Date }
        set {
            if let newValue {
                defaultsAccess.set(newValue, forKey: UserPreferencesKey.lastUpdateCheckDate)
            } else {
                defaultsAccess.removeObject(forKey: UserPreferencesKey.lastUpdateCheckDate)
            }
        }
    }

    /// Tag (e.g. `"v1.5.0"` or `"1.5.0"`) of the latest GitHub release the
    /// app has observed and that is strictly greater than the running
    /// version. `nil` means "no update to surface". Persisted so the
    /// FooterBar callout is visible immediately on launch when an update
    /// was already known.
    var latestUpdateTag: String? {
        get { defaultsAccess.string(forKey: UserPreferencesKey.latestUpdateTag) }
        set {
            if let newValue, !newValue.isEmpty {
                defaultsAccess.set(newValue, forKey: UserPreferencesKey.latestUpdateTag)
            } else {
                defaultsAccess.removeObject(forKey: UserPreferencesKey.latestUpdateTag)
            }
        }
    }

    /// `html_url` from the GitHub Releases API for the tag in
    /// `latestUpdateTag`. The FooterBar callout opens this URL.
    var latestUpdateURL: URL? {
        get {
            guard let raw = defaultsAccess.string(forKey: UserPreferencesKey.latestUpdateURL) else {
                return nil
            }
            return URL(string: raw)
        }
        set {
            if let newValue {
                defaultsAccess.set(newValue.absoluteString, forKey: UserPreferencesKey.latestUpdateURL)
            } else {
                defaultsAccess.removeObject(forKey: UserPreferencesKey.latestUpdateURL)
            }
        }
    }
}
