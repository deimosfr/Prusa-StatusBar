import SwiftUI

/// SwiftUI scene root. We use the SwiftUI App lifecycle for boot, but the
/// menu bar item is owned by `AppDelegate` (via `NSStatusItem`) because
/// `MenuBarExtra` doesn't reliably re-render its label on `@Observable` state
/// changes, the same workaround Sotto uses.
@main
struct PrusaStatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No windows declared here; the app is menu-bar only. `Settings { … }`
        // would create a default Preferences scene we don't want; our
        // PreferencesWindowController owns the actual window.
        Settings {
            EmptyView()
        }
    }
}
