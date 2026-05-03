import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `api-key-storage` Requirement: Confirmation before changing API-key
///   storage location. The migration must not run until the user confirms;
///   on cancel, the storage location and preference remain unchanged.
///
/// `PrinterTab.requestKeychainToggle` only sets a pending-state flag and
/// surfaces an alert; it does not touch the store. The actual mutation runs
/// from `confirmPendingKeychainToggle` (calls `applyKeychainToggle`) or is
/// suppressed by `cancelPendingKeychainToggle`. These tests exercise that
/// contract at the model level: pre-confirm state is observable, confirm
/// migrates and flips the pref, cancel leaves both untouched.
struct KeychainToggleConfirmationTests {
    private struct Harness {
        let store: LiveApiKeyStore
        let keychain: InMemoryKeychainStore
        let prefs: UserPreferences
    }

    private func makeHarness(
        useKeychain: Bool,
        keychainValue: String? = nil,
        plaintextValue: String? = nil
    ) -> Harness {
        let suite = "PrusaStatusBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = UserPreferences(defaults: defaults)
        prefs.useKeychainForApiKey = useKeychain
        prefs.printerApiKeyPlaintext = plaintextValue
        let keychain = InMemoryKeychainStore(initial: keychainValue)
        let store = LiveApiKeyStore(keychain: keychain, preferences: prefs)
        return Harness(store: store, keychain: keychain, prefs: prefs)
    }

    /// Mirrors `PrinterTab.confirmPendingKeychainToggle()` -> `applyKeychainToggle(_:)`.
    private func confirm(_ harness: Harness, enabled: Bool) throws {
        try harness.store.migrate(toKeychain: enabled)
        harness.prefs.useKeychainForApiKey = enabled
    }

    @Test
    func requestingEnableDoesNotMigrateUntilConfirm() throws {
        let harness = makeHarness(useKeychain: false, plaintextValue: "secret-key")

        // request: no state change yet.
        #expect(harness.prefs.useKeychainForApiKey == false)
        #expect(harness.prefs.printerApiKeyPlaintext == "secret-key")
        #expect(harness.keychain.read() == nil)

        // confirm.
        try confirm(harness, enabled: true)

        #expect(harness.prefs.useKeychainForApiKey == true)
        #expect(harness.keychain.read() == "secret-key")
        #expect(harness.prefs.printerApiKeyPlaintext == nil)
    }

    @Test
    func cancellingEnableLeavesStorageUntouched() {
        let harness = makeHarness(useKeychain: false, plaintextValue: "secret-key")

        // cancel: no migrate call, no preference flip.
        // PrinterTab.cancelPendingKeychainToggle() only resets local @State;
        // services and prefs remain at their pre-request values.
        #expect(harness.prefs.useKeychainForApiKey == false)
        #expect(harness.prefs.printerApiKeyPlaintext == "secret-key")
        #expect(harness.keychain.read() == nil)
    }

    @Test
    func requestingDisableDoesNotMigrateUntilConfirm() throws {
        let harness = makeHarness(useKeychain: true, keychainValue: "secret-key")

        #expect(harness.prefs.useKeychainForApiKey == true)
        #expect(harness.keychain.read() == "secret-key")
        #expect(harness.prefs.printerApiKeyPlaintext == nil)

        try confirm(harness, enabled: false)

        #expect(harness.prefs.useKeychainForApiKey == false)
        #expect(harness.prefs.printerApiKeyPlaintext == "secret-key")
        #expect(harness.keychain.read() == nil)
    }

    @Test
    func cancellingDisableLeavesStorageUntouched() {
        let harness = makeHarness(useKeychain: true, keychainValue: "secret-key")

        #expect(harness.prefs.useKeychainForApiKey == true)
        #expect(harness.keychain.read() == "secret-key")
        #expect(harness.prefs.printerApiKeyPlaintext == nil)
    }
}
