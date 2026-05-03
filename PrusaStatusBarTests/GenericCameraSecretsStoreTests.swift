import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Printer tab edits Generic Camera
///   (password follows useKeychainForApiKey toggle, migration on flip)
struct GenericCameraSecretsStoreTests {
    private struct Harness {
        let store: LiveGenericCameraSecretsStore
        let prefs: UserPreferences
        let keychain: InMemoryKeychainStore
    }

    private func makeHarness(useKeychain: Bool = true) -> Harness {
        let suite = "PrusaStatusBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = UserPreferences(defaults: defaults)
        prefs.useKeychainForApiKey = useKeychain
        let keychain = InMemoryKeychainStore()
        let store = LiveGenericCameraSecretsStore(preferences: prefs, keychain: keychain)
        return Harness(store: store, prefs: prefs, keychain: keychain)
    }

    @Test
    func writeWithToggleOnRoutesToKeychain() throws {
        let h = makeHarness(useKeychain: true)
        try h.store.write("s3cret")
        #expect(h.keychain.read() == "s3cret")
        #expect(h.prefs.genericCameraPasswordPlaintext == nil)
        #expect(h.store.read() == "s3cret")
    }

    @Test
    func writeWithToggleOffRoutesToPlaintext() throws {
        let h = makeHarness(useKeychain: false)
        try h.store.write("s3cret")
        #expect(h.keychain.read() == nil)
        #expect(h.prefs.genericCameraPasswordPlaintext == "s3cret")
        #expect(h.store.read() == "s3cret")
    }

    @Test
    func deleteClearsBothTiers() throws {
        let h = makeHarness(useKeychain: true)
        try h.store.write("s3cret")
        h.prefs.genericCameraPasswordPlaintext = "stale"
        try h.store.delete()
        #expect(h.keychain.read() == nil)
        #expect(h.prefs.genericCameraPasswordPlaintext == nil)
    }

    @Test
    func writeEmptyClears() throws {
        let h = makeHarness(useKeychain: true)
        try h.store.write("s3cret")
        try h.store.write("")
        #expect(h.store.read() == nil)
    }

    @Test
    func migrateToPlaintextMovesValue() throws {
        let h = makeHarness(useKeychain: true)
        try h.store.write("s3cret")
        try h.store.migrate(toKeychain: false)
        #expect(h.keychain.read() == nil)
        #expect(h.prefs.genericCameraPasswordPlaintext == "s3cret")
    }

    @Test
    func migrateToKeychainMovesValue() throws {
        let h = makeHarness(useKeychain: false)
        try h.store.write("s3cret")
        try h.store.migrate(toKeychain: true)
        #expect(h.prefs.genericCameraPasswordPlaintext == nil)
        #expect(h.keychain.read() == "s3cret")
    }

    @Test
    func roundTripPlaintextToKeychainAndBack() throws {
        let h = makeHarness(useKeychain: false)
        try h.store.write("s3cret")
        // -> Keychain
        h.prefs.useKeychainForApiKey = true
        try h.store.migrate(toKeychain: true)
        #expect(h.store.read() == "s3cret")
        // -> back to plaintext
        h.prefs.useKeychainForApiKey = false
        try h.store.migrate(toKeychain: false)
        #expect(h.store.read() == "s3cret")
    }

    @Test
    func readMissingReturnsNil() {
        let h = makeHarness(useKeychain: true)
        #expect(h.store.read() == nil)
    }
}
