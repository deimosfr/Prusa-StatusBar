import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `api-key-storage` (modified) Requirement: per-slot custom-action
///   secrets follow the same Keychain toggle as the API key, with
///   migration moving every slot in one flow.
struct CustomActionSecretsStoreTests {
    private struct Harness {
        let store: LiveCustomActionSecretsStore
        let prefs: UserPreferences
        let keychains: [CustomActionSlot: InMemoryKeychainStore]
    }

    private func makeHarness(useKeychain: Bool = true) -> Harness {
        let suite = "PrusaStatusBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = UserPreferences(defaults: defaults)
        prefs.useKeychainForApiKey = useKeychain
        var built: [CustomActionSlot: InMemoryKeychainStore] = [:]
        for slot in CustomActionSlot.allCases {
            built[slot] = InMemoryKeychainStore()
        }
        let keychains = built
        let store = LiveCustomActionSecretsStore(
            preferences: prefs,
            keychainFactory: { slot in keychains[slot]! }
        )
        return Harness(store: store, prefs: prefs, keychains: keychains)
    }

    private func sample() -> CustomActionSecrets {
        CustomActionSecrets(
            url: "https://example.com/api",
            body: "{\"x\":1}",
            headerValues: [UUID().uuidString: "Bearer xyz"]
        )
    }

    @Test
    func writeWithToggleOnRoutesToKeychain() throws {
        let h = makeHarness(useKeychain: true)
        let secrets = sample()
        try h.store.write(secrets, slot: .headerLeft)

        let stored = try #require(h.keychains[.headerLeft]?.read())
        #expect(!stored.isEmpty)
        #expect(h.prefs.customActionSecretPlaintext(slot: .headerLeft) == nil)

        let read = h.store.read(slot: .headerLeft)
        #expect(read == secrets)
    }

    @Test
    func writeWithToggleOffRoutesToPlaintext() throws {
        let h = makeHarness(useKeychain: false)
        let secrets = sample()
        try h.store.write(secrets, slot: .rowRight)

        #expect(h.keychains[.rowRight]?.read() == nil)
        #expect(h.prefs.customActionSecretPlaintext(slot: .rowRight) != nil)

        let read = h.store.read(slot: .rowRight)
        #expect(read == secrets)
    }

    @Test
    func deleteClearsBothTiers() throws {
        let h = makeHarness(useKeychain: true)
        try h.store.write(sample(), slot: .rowLeft)
        h.prefs.setCustomActionSecretPlaintext("stale", slot: .rowLeft)

        try h.store.delete(slot: .rowLeft)
        #expect(h.keychains[.rowLeft]?.read() == nil)
        #expect(h.prefs.customActionSecretPlaintext(slot: .rowLeft) == nil)
    }

    @Test
    func migrateToPlaintextMovesEverySlot() throws {
        let h = makeHarness(useKeychain: true)
        for slot in CustomActionSlot.allCases {
            try h.store.write(sample(), slot: slot)
        }

        try h.store.migrate(toKeychain: false)
        for slot in CustomActionSlot.allCases {
            #expect(h.keychains[slot]?.read() == nil)
            #expect(h.prefs.customActionSecretPlaintext(slot: slot) != nil)
        }
    }

    @Test
    func migrateToKeychainMovesEverySlot() throws {
        let h = makeHarness(useKeychain: false)
        for slot in CustomActionSlot.allCases {
            try h.store.write(sample(), slot: slot)
        }

        try h.store.migrate(toKeychain: true)
        for slot in CustomActionSlot.allCases {
            #expect(h.prefs.customActionSecretPlaintext(slot: slot) == nil)
            #expect(try !#require(h.keychains[slot]?.read()).isEmpty)
        }
    }

    @Test
    func roundTripPlaintextToKeychainAndBack() throws {
        let h = makeHarness(useKeychain: false)
        let original = sample()
        try h.store.write(original, slot: .headerRight)

        // -> Keychain
        h.prefs.useKeychainForApiKey = true
        try h.store.migrate(toKeychain: true)
        #expect(h.store.read(slot: .headerRight) == original)

        // -> back to plaintext
        h.prefs.useKeychainForApiKey = false
        try h.store.migrate(toKeychain: false)
        #expect(h.store.read(slot: .headerRight) == original)
    }

    @Test
    func readMissingSlotReturnsNil() {
        let h = makeHarness(useKeychain: true)
        #expect(h.store.read(slot: .headerLeft) == nil)
    }
}
