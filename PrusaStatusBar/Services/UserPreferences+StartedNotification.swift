import Foundation

public extension UserPreferences {
    /// Per-state opt-in for the "Print starting" banner. Defaults OFF: the
    /// event is new in this release and existing users should not get an
    /// extra banner without explicitly asking for it.
    var notifyOnStarted: Bool {
        get { defaultsAccess.bool(forKey: UserPreferencesKey.notifyOnStarted) }
        set { defaultsAccess.set(newValue, forKey: UserPreferencesKey.notifyOnStarted) }
    }
}
