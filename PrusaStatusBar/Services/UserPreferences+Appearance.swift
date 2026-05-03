import Foundation

/// Appearance-related preference accessors carved out of
/// `UserPreferences` so that file stays under the lint budget. Covers
/// the disconnected-icon style + emoji slot and the progress-bar style.
public extension UserPreferences {
    /// User-selected style for the menu-bar icon while disconnected.
    /// Defaults to `.default` (bundled `IconDisconnected` asset). Unknown
    /// raw values fall back to the default and are overwritten on the
    /// next user selection.
    var disconnectedIconStyle: DisconnectedIconStyle {
        get {
            guard let raw = defaultsAccess.string(forKey: UserPreferencesKey.disconnectedIconStyle),
                  let value = DisconnectedIconStyle(rawValue: raw)
            else {
                return .default
            }
            return value
        }
        set {
            defaultsAccess.set(newValue.rawValue, forKey: UserPreferencesKey.disconnectedIconStyle)
        }
    }

    /// User-chosen emoji shown while disconnected when
    /// `disconnectedIconStyle == .emoji`. Whitespace-only / empty writes
    /// remove the key so reads fall back to the default. Trimmed on read
    /// so a stray space does not blank the menu bar.
    var disconnectedIconEmoji: String {
        get {
            let raw = defaultsAccess.string(forKey: UserPreferencesKey.disconnectedIconEmoji) ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? Self.disconnectedIconEmojiDefault : trimmed
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaultsAccess.removeObject(forKey: UserPreferencesKey.disconnectedIconEmoji)
            } else {
                defaultsAccess.set(trimmed, forKey: UserPreferencesKey.disconnectedIconEmoji)
            }
        }
    }

    /// User-selected progress bar style for the dropdown's Job Card.
    /// Defaults to `.spool` (the on-brand variant). Unknown raw values
    /// fall back to the default and are overwritten on the next user
    /// selection.
    var progressBarStyle: ProgressBarStyle {
        get {
            guard let raw = defaultsAccess.string(forKey: UserPreferencesKey.progressBarStyle),
                  let value = ProgressBarStyle(rawValue: raw)
            else {
                return .spool
            }
            return value
        }
        set {
            defaultsAccess.set(newValue.rawValue, forKey: UserPreferencesKey.progressBarStyle)
        }
    }
}
