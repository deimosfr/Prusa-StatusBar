import Foundation

/// Bag of injected services that the rest of the app reads through. Built once
/// in `AppDelegate.applicationDidFinishLaunching` so individual components
/// don't need to know how to construct anything, they just receive the
/// closures and protocols they need.
@MainActor
public final class AppServices {
    public let settings: UserPreferences
    public let keychain: KeychainStore
    public let apiKeyStore: ApiKeyStore
    public let customActionSecretsStore: CustomActionSecretsStore
    public let genericCameraSecretsStore: GenericCameraSecretsStore
    public let customActionRunner: CustomActionRunning
    public let rtspProbe: RTSPProbing
    public let client: PrusaLinkClient
    public let notifier: NotificationService
    public let loginItem: LoginItemService

    /// Called by Preferences when URL or API key change so the polling loop
    /// picks up the new configuration on the next cycle. The closure runs on
    /// the main actor, both because every call site is already on
    /// `@MainActor` and because the implementation pokes at UI-bound state.
    public let onConfigurationChanged: @MainActor () -> Void

    /// Called when the user re-enables the "Check for updates" toggle so
    /// the app can fire a fresh GitHub Releases check immediately rather
    /// than waiting for the next hourly wake.
    public let onRequestUpdateCheck: @MainActor () -> Void

    public init(
        settings: UserPreferences,
        keychain: KeychainStore,
        apiKeyStore: ApiKeyStore,
        customActionSecretsStore: CustomActionSecretsStore,
        genericCameraSecretsStore: GenericCameraSecretsStore,
        customActionRunner: CustomActionRunning,
        rtspProbe: RTSPProbing,
        client: PrusaLinkClient,
        notifier: NotificationService,
        loginItem: LoginItemService,
        onConfigurationChanged: @escaping @MainActor () -> Void,
        onRequestUpdateCheck: @escaping @MainActor () -> Void = {}
    ) {
        self.settings = settings
        self.keychain = keychain
        self.apiKeyStore = apiKeyStore
        self.customActionSecretsStore = customActionSecretsStore
        self.genericCameraSecretsStore = genericCameraSecretsStore
        self.customActionRunner = customActionRunner
        self.rtspProbe = rtspProbe
        self.client = client
        self.notifier = notifier
        self.loginItem = loginItem
        self.onConfigurationChanged = onConfigurationChanged
        self.onRequestUpdateCheck = onRequestUpdateCheck
    }
}
