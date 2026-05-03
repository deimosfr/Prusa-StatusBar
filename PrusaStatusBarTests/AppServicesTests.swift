import Foundation
@testable import PrusaStatusBar
import Testing

/// Verifies the dependency-injection container hands the same protocol
/// instances back to readers and that the closure-based callbacks
/// (`onConfigurationChanged`, `onRequestUpdateCheck`) fire when the host
/// invokes them.
@MainActor
struct AppServicesTests {
    private func makeServices(
        onConfigurationChanged: @escaping @MainActor () -> Void = {},
        onRequestUpdateCheck: @escaping @MainActor () -> Void = {}
    ) -> AppServices {
        let suite = "AppServicesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = UserPreferences(defaults: defaults)
        let keychain = InMemoryKeychainStore()
        return AppServices(
            settings: preferences,
            keychain: keychain,
            apiKeyStore: LiveApiKeyStore(keychain: keychain, preferences: preferences),
            customActionSecretsStore: InMemoryCustomActionSecretsStore(),
            genericCameraSecretsStore: InMemoryGenericCameraSecretsStore(),
            customActionRunner: StubCustomActionRunner(),
            rtspProbe: StubRTSPProbe(stubResult: .success(
                RTSPDescribeInfo(sessionDescription: nil, mediaLines: [])
            )),
            client: StubPrusaLinkClient(),
            notifier: StubNotificationService(),
            loginItem: StubLoginItemService(),
            onConfigurationChanged: onConfigurationChanged,
            onRequestUpdateCheck: onRequestUpdateCheck
        )
    }

    @Test
    func storesAllInjectedDependencies() {
        let services = makeServices()
        #expect(services.keychain is InMemoryKeychainStore)
        #expect(services.apiKeyStore is LiveApiKeyStore)
        #expect(services.customActionSecretsStore is InMemoryCustomActionSecretsStore)
        #expect(services.genericCameraSecretsStore is InMemoryGenericCameraSecretsStore)
        #expect(services.customActionRunner is StubCustomActionRunner)
        #expect(services.rtspProbe is StubRTSPProbe)
        #expect(services.client is StubPrusaLinkClient)
        #expect(services.notifier is StubNotificationService)
        #expect(services.loginItem is StubLoginItemService)
    }

    @Test
    func onConfigurationChangedFiresProvidedClosure() {
        var hits = 0
        let services = makeServices(onConfigurationChanged: { hits += 1 })
        services.onConfigurationChanged()
        services.onConfigurationChanged()
        #expect(hits == 2)
    }

    @Test
    func onRequestUpdateCheckFiresProvidedClosure() {
        var hits = 0
        let services = makeServices(onRequestUpdateCheck: { hits += 1 })
        services.onRequestUpdateCheck()
        #expect(hits == 1)
    }

    @Test
    func defaultOnRequestUpdateCheckIsNoop() {
        let services = makeServices()
        services.onRequestUpdateCheck()
    }
}
