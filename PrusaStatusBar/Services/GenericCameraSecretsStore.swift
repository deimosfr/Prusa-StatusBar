import Foundation

/// Routes the optional generic-camera password to either the macOS Keychain
/// or the plaintext `UserDefaults` slot, based on the user's
/// `useKeychainForApiKey` preference (the same toggle that gates the
/// PrusaLink API key and per-slot custom-action secrets). Reusing the
/// toggle keeps the UX simple: one decision covers every secret.
public protocol GenericCameraSecretsStore: Sendable {
    func read() -> String?
    func write(_ value: String) throws
    func delete() throws
    /// Move the password between the Keychain and the plaintext
    /// `UserDefaults` slot. Callers flip
    /// `UserPreferences.useKeychainForApiKey` themselves before or after
    /// migration; this method only handles the data move so a crash midway
    /// leaves at most a duplicated copy, never lost data.
    func migrate(toKeychain destinationIsKeychain: Bool) throws
}

public final class LiveGenericCameraSecretsStore: GenericCameraSecretsStore, @unchecked Sendable {
    private let preferences: UserPreferences
    private let keychain: KeychainStore

    public init(
        preferences: UserPreferences,
        keychain: KeychainStore = SystemKeychainStore(account: "generic-camera-password")
    ) {
        self.preferences = preferences
        self.keychain = keychain
    }

    public func read() -> String? {
        let raw: String? = preferences.useKeychainForApiKey
            ? keychain.read()
            : preferences.genericCameraPasswordPlaintext
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    public func write(_ value: String) throws {
        if value.isEmpty {
            try delete()
            return
        }
        if preferences.useKeychainForApiKey {
            try keychain.write(value)
            preferences.genericCameraPasswordPlaintext = nil
        } else {
            preferences.genericCameraPasswordPlaintext = value
            try? keychain.delete()
        }
    }

    public func delete() throws {
        try? keychain.delete()
        preferences.genericCameraPasswordPlaintext = nil
    }

    public func migrate(toKeychain destinationIsKeychain: Bool) throws {
        if destinationIsKeychain {
            if let value = preferences.genericCameraPasswordPlaintext, !value.isEmpty {
                try keychain.write(value)
            }
            preferences.genericCameraPasswordPlaintext = nil
        } else {
            if let value = keychain.read(), !value.isEmpty {
                preferences.genericCameraPasswordPlaintext = value
            }
            try? keychain.delete()
        }
    }
}

/// In-memory implementation for tests and prototype mode.
public final class InMemoryGenericCameraSecretsStore: GenericCameraSecretsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(initial: String? = nil) {
        value = initial
    }

    public func read() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func write(_ value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        self.value = value.isEmpty ? nil : value
    }

    public func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        value = nil
    }

    public func migrate(toKeychain _: Bool) throws {
        // No-op: in-memory store has only one tier.
    }
}
