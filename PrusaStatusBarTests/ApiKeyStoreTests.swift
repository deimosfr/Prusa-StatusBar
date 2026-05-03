import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `api-key-storage` Requirement: API key persistence honors a
///   user-controlled storage toggle (toggle ON write, toggle OFF write,
///   migration both directions, read honors active store).
struct ApiKeyStoreTests {
    private struct Harness {
        let store: LiveApiKeyStore
        let keychain: InMemoryKeychainStore
        let prefs: UserPreferences
    }

    private func makeHarness(useKeychain: Bool = true, initialKeychainValue: String? = nil) -> Harness {
        let suite = "PrusaStatusBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = UserPreferences(defaults: defaults)
        prefs.useKeychainForApiKey = useKeychain
        let keychain = InMemoryKeychainStore(initial: initialKeychainValue)
        let store = LiveApiKeyStore(keychain: keychain, preferences: prefs)
        return Harness(store: store, keychain: keychain, prefs: prefs)
    }

    @Test
    func writeWithToggleOnRoutesToKeychain() throws {
        let harness = makeHarness(useKeychain: true)
        try harness.store.write("secret-key")
        #expect(harness.keychain.read() == "secret-key")
        #expect(harness.prefs.printerApiKeyPlaintext == nil)
    }

    @Test
    func writeWithToggleOffRoutesToUserDefaults() throws {
        let harness = makeHarness(useKeychain: false)
        try harness.store.write("secret-key")
        #expect(harness.prefs.printerApiKeyPlaintext == "secret-key")
        #expect(harness.keychain.read() == nil)
    }

    @Test
    func readPrefersActiveStore() {
        let harness = makeHarness(useKeychain: true, initialKeychainValue: "from-keychain")
        harness.prefs.printerApiKeyPlaintext = "stale-plaintext"
        #expect(harness.store.read() == "from-keychain")
        harness.prefs.useKeychainForApiKey = false
        #expect(harness.store.read() == "stale-plaintext")
    }

    @Test
    func migrateToPlaintextMovesValueAndClearsKeychain() throws {
        let harness = makeHarness(useKeychain: true, initialKeychainValue: "movable")
        try harness.store.migrate(toKeychain: false)
        #expect(harness.prefs.printerApiKeyPlaintext == "movable")
        #expect(harness.keychain.read() == nil)
    }

    @Test
    func migrateToKeychainMovesValueAndClearsPlaintext() throws {
        let harness = makeHarness(useKeychain: false)
        harness.prefs.printerApiKeyPlaintext = "movable"
        try harness.store.migrate(toKeychain: true)
        #expect(harness.keychain.read() == "movable")
        #expect(harness.prefs.printerApiKeyPlaintext == nil)
    }

    @Test
    func deleteClearsBothStores() throws {
        let harness = makeHarness(useKeychain: true, initialKeychainValue: "in-keychain")
        harness.prefs.printerApiKeyPlaintext = "in-defaults"
        try harness.store.delete()
        #expect(harness.keychain.read() == nil)
        #expect(harness.prefs.printerApiKeyPlaintext == nil)
    }

    @Test
    func emptyKeychainValueReadsAsNil() {
        let harness = makeHarness(useKeychain: true, initialKeychainValue: "")
        #expect(harness.store.read() == nil)
    }

    @Test
    func migrateNoOpWhenSourceEmpty() throws {
        let harness = makeHarness(useKeychain: true)
        try harness.store.migrate(toKeychain: false)
        #expect(harness.prefs.printerApiKeyPlaintext == nil)
        #expect(harness.keychain.read() == nil)
    }
}
