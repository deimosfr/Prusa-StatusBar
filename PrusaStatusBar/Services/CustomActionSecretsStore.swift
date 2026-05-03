import Foundation

/// Routes custom action secret reads, writes, and deletes to either the
/// macOS Keychain or a per-slot `UserDefaults` plaintext slot, based on
/// the user's `useKeychainForApiKey` preference (the same toggle that
/// gates the PrusaLink API key). Reusing one toggle keeps the UX simple:
/// the user opts in to Keychain protection once and it covers every
/// piece of sensitive info the app persists.
public protocol CustomActionSecretsStore: Sendable {
    func read(slot: CustomActionSlot) -> CustomActionSecrets?
    func write(_ secrets: CustomActionSecrets, slot: CustomActionSlot) throws
    func delete(slot: CustomActionSlot) throws
    /// Move every slot's secrets between the Keychain and the plaintext
    /// `UserDefaults` slot. Callers flip
    /// `UserPreferences.useKeychainForApiKey` themselves before or after
    /// migration; this method only handles the data move so a crash midway
    /// leaves at most duplicated copies, never lost data.
    func migrate(toKeychain destinationIsKeychain: Bool) throws
}

public final class LiveCustomActionSecretsStore: CustomActionSecretsStore, @unchecked Sendable {
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    private let preferences: UserPreferences
    private let keychainFactory: @Sendable (CustomActionSlot) -> KeychainStore

    public init(
        preferences: UserPreferences,
        keychainFactory: @Sendable @escaping (CustomActionSlot) -> KeychainStore = { slot in
            SystemKeychainStore(account: "custom-action-secrets-\(slot.rawValue)")
        }
    ) {
        self.preferences = preferences
        self.keychainFactory = keychainFactory
    }

    public func read(slot: CustomActionSlot) -> CustomActionSecrets? {
        let raw: String? = preferences.useKeychainForApiKey
            ? keychainFactory(slot).read()
            : preferences.customActionSecretPlaintext(slot: slot)
        guard let raw, !raw.isEmpty else { return nil }
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? Self.decoder.decode(CustomActionSecrets.self, from: data)
    }

    public func write(_ secrets: CustomActionSecrets, slot: CustomActionSlot) throws {
        let data = try Self.encoder.encode(secrets)
        guard let json = String(data: data, encoding: .utf8) else {
            throw KeychainError.unhandled(errSecParam)
        }
        if preferences.useKeychainForApiKey {
            try keychainFactory(slot).write(json)
            preferences.setCustomActionSecretPlaintext(nil, slot: slot)
        } else {
            preferences.setCustomActionSecretPlaintext(json, slot: slot)
            try? keychainFactory(slot).delete()
        }
    }

    public func delete(slot: CustomActionSlot) throws {
        try? keychainFactory(slot).delete()
        preferences.setCustomActionSecretPlaintext(nil, slot: slot)
    }

    public func migrate(toKeychain destinationIsKeychain: Bool) throws {
        for slot in CustomActionSlot.allCases {
            let store = keychainFactory(slot)
            if destinationIsKeychain {
                if let value = preferences.customActionSecretPlaintext(slot: slot), !value.isEmpty {
                    try store.write(value)
                }
                preferences.setCustomActionSecretPlaintext(nil, slot: slot)
            } else {
                if let value = store.read(), !value.isEmpty {
                    preferences.setCustomActionSecretPlaintext(value, slot: slot)
                }
                try? store.delete()
            }
        }
    }
}

/// In-memory implementation for tests and prototype mode.
public final class InMemoryCustomActionSecretsStore: CustomActionSecretsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CustomActionSlot: CustomActionSecrets] = [:]

    public init() {}

    public func read(slot: CustomActionSlot) -> CustomActionSecrets? {
        lock.lock()
        defer { lock.unlock() }
        return values[slot]
    }

    public func write(_ secrets: CustomActionSecrets, slot: CustomActionSlot) throws {
        lock.lock()
        defer { lock.unlock() }
        values[slot] = secrets
    }

    public func delete(slot: CustomActionSlot) throws {
        lock.lock()
        defer { lock.unlock() }
        values[slot] = nil
    }

    public func migrate(toKeychain _: Bool) throws {
        // No-op: in-memory store has only one tier.
    }
}
