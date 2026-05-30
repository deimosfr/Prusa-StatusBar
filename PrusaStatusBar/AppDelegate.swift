import AppKit
import Darwin
import Dispatch
import Foundation

/// Wires the app's services together and owns the menu bar / preferences
/// controllers. Kept on `@MainActor` because everything it touches is UI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    /// Injection seam for the duplicate-launch guard. Tests swap in a fake.
    var runningInstancesProvider: RunningInstancesProvider = SystemRunningInstancesProvider()

    /// Bundle of long-lived services and controllers populated once in
    /// `applicationDidFinishLaunching`. Wrapping them in a single optional
    /// (instead of five implicitly-unwrapped properties) means a stray access
    /// before launch surfaces as a clean nil rather than a crash.
    private struct Wired {
        let services: AppServices
        let coordinator: PollingCoordinator
        let updateChecker: UpdateChecker
        let menuBar: MenuBarController
        let preferences: PreferencesWindowController
    }

    private var wired: Wired?

    func applicationWillFinishLaunching(_: Notification) {
        #if !PROTOTYPE_MODE
            // Skip the guard under XCTest: the test host is the same bundle as
            // the production app, so a developer running the suite while the
            // app is also open in their session would have the test runner
            // killed before it could establish its xpc connection.
            guard NSClassFromString("XCTestCase") == nil,
                  ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil,
                  ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            else { return }
            if let existing = existingInstance(forBundleID: Bundle.main.bundleIdentifier) {
                Log.lifecycle.info("Duplicate launch detected; activating existing instance and exiting")
                existing.activate(options: [.activateAllWindows])
                NSApp.terminate(nil)
            }
        #endif
    }

    /// Returns another running app with the same bundle identifier, or nil if
    /// this is the only instance. Pure helper carved out so unit tests can
    /// exercise the lookup without invoking `NSApp.terminate`.
    func existingInstance(forBundleID bundleID: String?) -> NSRunningApplication? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return runningInstancesProvider.otherInstances(bundleIdentifier: bundleID).first
    }

    func applicationDidFinishLaunching(_: Notification) {
        Log.lifecycle.info("App launched")
        // Menu-bar app, no Dock icon, no Cmd-Tab entry.
        NSApp.setActivationPolicy(.accessory)

        let settings = UserPreferences()
        let services = buildServices(settings: settings)
        // Hydrate the model from disk before any UI renders.
        hydrateModel(from: services)
        let wired = buildWired(services: services, settings: settings)
        self.wired = wired

        wired.coordinator.start()
        wired.updateChecker.start()
        seedNotificationAuthorization(notifier: services.notifier)
    }

    private func buildServices(settings: UserPreferences) -> AppServices {
        let keychain: KeychainStore = makeKeychain()
        let apiKeyStore: ApiKeyStore = LiveApiKeyStore(keychain: keychain, preferences: settings)
        let client: PrusaLinkClient = makeClient(settings: settings, apiKeyStore: apiKeyStore)

        return AppServices(
            settings: settings,
            keychain: keychain,
            apiKeyStore: apiKeyStore,
            customActionSecretsStore: makeCustomActionSecretsStore(settings: settings),
            genericCameraSecretsStore: makeGenericCameraSecretsStore(settings: settings),
            customActionRunner: makeCustomActionRunner(),
            rtspProbe: makeRTSPProbe(),
            client: client,
            notifier: makeNotificationService(),
            loginItem: makeLoginItemService(),
            onConfigurationChanged: { [weak self] in
                guard let self, let wired else { return }
                (wired.services.client as? URLSessionPrusaLinkClient)?.invalidateConfigurationCache()
                hydrateModel(from: wired.services)
                model.printerInfo = nil
                wired.coordinator.refreshNow()
            },
            onRequestUpdateCheck: { [weak self] in
                guard let checker = self?.wired?.updateChecker else { return }
                Task { @MainActor in await checker.checkNow() }
            }
        )
    }

    private func buildWired(services: AppServices, settings: UserPreferences) -> Wired {
        let coordinator = makeCoordinator(client: services.client, notifier: services.notifier)
        let preferences = PreferencesWindowController(model: model, services: services)
        let menuBar = MenuBarController(
            model: model,
            coordinator: coordinator,
            openPreferences: { [weak self] in self?.wired?.preferences.present() },
            openPrinterPreferences: { [weak self] in self?.wired?.preferences.present(tab: .printer) },
            customActionRunner: services.customActionRunner,
            notifier: services.notifier
        )
        let updateChecker = UpdateChecker(
            model: model,
            client: makeReleaseClient(),
            preferences: settings
        )
        return Wired(
            services: services,
            coordinator: coordinator,
            updateChecker: updateChecker,
            menuBar: menuBar,
            preferences: preferences
        )
    }

    /// Synchronous shutdown hook. Runs even when other subsystems return
    /// `.terminateLater`, so the helper is dead before the app actually
    /// exits. `applicationWillTerminate` keeps running as a backup.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        Log.lifecycle.info("App should terminate")
        ActiveCameraPlayers.shared.stopAll()
        return .terminateNow
    }

    func applicationWillTerminate(_: Notification) {
        Log.lifecycle.info("App terminating")
        wired?.coordinator.stop()
        wired?.updateChecker.stop()
        ActiveCameraPlayers.shared.stopAll()
    }

    /// Pull the live `UNAuthorizationStatus` and mirror it onto the model so
    /// the General tab can show the inline warning row when banners would be
    /// silently swallowed by the OS.
    func refreshNotificationAuthorization() async {
        guard let services = wired?.services else { return }
        let status = await services.notifier.authorizationStatus()
        model.notificationsAuthorized = (status == .authorized || status == .provisional)
    }

    /// On launch: prompt for authorization when the master toggle is ON, then
    /// mirror the current status into the model. When the toggle is OFF we
    /// skip the prompt but still refresh the cached status so the warning row
    /// has accurate data the moment the user flips ON.
    private func seedNotificationAuthorization(notifier: NotificationService) {
        if model.notificationsEnabled {
            Task { @MainActor [weak self] in
                _ = await notifier.requestAuthorization()
                await self?.refreshNotificationAuthorization()
            }
        } else {
            Task { @MainActor [weak self] in
                await self?.refreshNotificationAuthorization()
            }
        }
    }

    // MARK: - Service factories (swap stubs in prototype mode)

    private func makeClient(settings: UserPreferences, apiKeyStore: ApiKeyStore) -> PrusaLinkClient {
        #if PROTOTYPE_MODE
            return StubPrusaLinkClient()
        #else
            return URLSessionPrusaLinkClient(configurationProvider: {
                guard
                    let urlString = settings.printerBaseURL,
                    let baseURL = URL(string: urlString),
                    let key = apiKeyStore.read(),
                    !key.isEmpty
                else {
                    return nil
                }
                let fallbackBaseURL = settings.printerBaseURLSecondary
                    .flatMap { URL(string: $0) }
                return PrusaLinkConfiguration(
                    baseURL: baseURL,
                    apiKey: key,
                    fallbackBaseURL: fallbackBaseURL
                )
            })
        #endif
    }

    private func makeReleaseClient() -> GitHubReleaseClient {
        #if PROTOTYPE_MODE
            return StubGitHubReleaseClient()
        #else
            return URLSessionGitHubReleaseClient()
        #endif
    }

    private func makeKeychain() -> KeychainStore {
        #if PROTOTYPE_MODE
            return InMemoryKeychainStore(initial: "stub-key")
        #else
            return SystemKeychainStore()
        #endif
    }

    private func makeCustomActionSecretsStore(settings: UserPreferences) -> CustomActionSecretsStore {
        #if PROTOTYPE_MODE
            return InMemoryCustomActionSecretsStore()
        #else
            return LiveCustomActionSecretsStore(preferences: settings)
        #endif
    }

    private func makeGenericCameraSecretsStore(settings: UserPreferences) -> GenericCameraSecretsStore {
        #if PROTOTYPE_MODE
            return InMemoryGenericCameraSecretsStore()
        #else
            return LiveGenericCameraSecretsStore(preferences: settings)
        #endif
    }

    private func makeCustomActionRunner() -> CustomActionRunning {
        #if PROTOTYPE_MODE
            return StubCustomActionRunner()
        #else
            return LiveCustomActionRunner()
        #endif
    }

    private func makeRTSPProbe() -> RTSPProbing {
        #if PROTOTYPE_MODE
            return StubRTSPProbe(stubResult: .success(
                RTSPDescribeInfo(sessionDescription: "Stub camera", mediaLines: ["video 0 RTP/AVP 96"])
            ))
        #else
            return LiveRTSPProbe()
        #endif
    }

    private func makeNotificationService() -> NotificationService {
        #if PROTOTYPE_MODE
            return StubNotificationService()
        #else
            return UNNotificationService()
        #endif
    }

    private func makeLoginItemService() -> LoginItemService {
        #if PROTOTYPE_MODE
            return StubLoginItemService()
        #else
            return SMAppLoginItemService()
        #endif
    }

    private func makeCameraSnapshotService() -> CameraSnapshotService {
        #if PROTOTYPE_MODE
            return StubCameraSnapshotService()
        #else
            return LiveCameraSnapshotService(model: model)
        #endif
    }

    private func makeCoordinator(client: PrusaLinkClient, notifier: NotificationService) -> PollingCoordinator {
        PollingCoordinator(
            model: model,
            client: client,
            notifier: notifier,
            snapshotService: makeCameraSnapshotService()
        )
    }

    // MARK: - Configuration <-> model sync

    private func hydrateModel(from services: AppServices) {
        model.hydrate(from: services)
        #if PROTOTYPE_MODE
            // Pretend the printer is configured so the dropdown shows real-looking
            // data even though no real network call happens.
            model.printerBaseURL = "http://prusa-stub.local"
            model.apiKeyConfigured = true
        #endif
    }
}
