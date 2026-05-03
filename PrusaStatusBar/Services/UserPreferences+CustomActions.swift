import Foundation

/// Custom-action persistence accessors carved out of `UserPreferences` so
/// that file stays under the lint budget. The split mirrors the public /
/// secrets divide: this file owns only the non-sensitive half plus the
/// per-slot plaintext fallback that activates when the Keychain toggle
/// is off.
public extension UserPreferences {
    /// Persisted public half of the four custom action slots, JSON-encoded
    /// `[CustomActionSlot.rawValue: CustomActionPublicConfig]`. The
    /// sensitive half (URL, header values, body) lives in the Keychain or
    /// per-slot plaintext fallback via `CustomActionSecretsStore`.
    var customActionsPublicJSON: String {
        get { defaultsAccess.string(forKey: UserPreferencesKey.customActionsPublicJSON) ?? "" }
        set { defaultsAccess.set(newValue, forKey: UserPreferencesKey.customActionsPublicJSON) }
    }

    /// Recently-picked SF Symbol names, most-recent-first, capped at 8.
    /// Pinned at the top of the symbol picker sheet for quick reuse across
    /// the four slots. Empty when the user has never picked.
    var recentSymbols: [String] {
        get {
            (defaultsAccess.array(forKey: UserPreferencesKey.recentSymbols) as? [String]) ?? []
        }
        set {
            let trimmed = Array(newValue.prefix(8))
            defaultsAccess.set(trimmed, forKey: UserPreferencesKey.recentSymbols)
        }
    }

    /// Plaintext fallback slot for one custom action's secrets bundle,
    /// used only when `useKeychainForApiKey == false`. The Keychain remains
    /// the default; this slot is kept `nil` whenever the toggle is ON.
    func customActionSecretPlaintext(slot: CustomActionSlot) -> String? {
        defaultsAccess.string(forKey: UserPreferencesKey.customActionSecretPlaintext(slot: slot))
    }

    func setCustomActionSecretPlaintext(_ value: String?, slot: CustomActionSlot) {
        let key = UserPreferencesKey.customActionSecretPlaintext(slot: slot)
        if let value, !value.isEmpty {
            defaultsAccess.set(value, forKey: key)
        } else {
            defaultsAccess.removeObject(forKey: key)
        }
    }
}
