import Foundation

/// Routes PrusaLink API-key reads, writes and deletes to either the macOS
/// Keychain or a `UserDefaults` plaintext slot, based on the user's
/// `useKeychainForApiKey` preference. The preference defaults to ON; the
/// plaintext path exists only because the user has explicitly opted out via
/// the Security toggle on the Printer tab.
public protocol ApiKeyStore: Sendable {
    func read() -> String?
    func write(_ value: String) throws
    func delete() throws
    /// Move the current API key to the requested store and clear the other.
    /// Callers flip `UserPreferences.useKeychainForApiKey` themselves, before
    /// or after migration; this method only handles the data move so a crash
    /// midway leaves at most a duplicated value, never a lost one.
    func migrate(toKeychain destinationIsKeychain: Bool) throws
}

public final class LiveApiKeyStore: ApiKeyStore, @unchecked Sendable {
    private let keychain: KeychainStore
    private let preferences: UserPreferences

    public init(keychain: KeychainStore, preferences: UserPreferences) {
        self.keychain = keychain
        self.preferences = preferences
    }

    public func read() -> String? {
        if preferences.useKeychainForApiKey {
            let value = keychain.read()
            return (value?.isEmpty ?? true) ? nil : value
        } else {
            let value = preferences.printerApiKeyPlaintext
            return (value?.isEmpty ?? true) ? nil : value
        }
    }

    public func write(_ value: String) throws {
        if preferences.useKeychainForApiKey {
            try keychain.write(value)
            preferences.printerApiKeyPlaintext = nil
        } else {
            preferences.printerApiKeyPlaintext = value
            try? keychain.delete()
        }
    }

    public func delete() throws {
        try? keychain.delete()
        preferences.printerApiKeyPlaintext = nil
    }

    public func migrate(toKeychain destinationIsKeychain: Bool) throws {
        if destinationIsKeychain {
            if let value = preferences.printerApiKeyPlaintext, !value.isEmpty {
                try keychain.write(value)
            }
            preferences.printerApiKeyPlaintext = nil
        } else {
            if let value = keychain.read(), !value.isEmpty {
                preferences.printerApiKeyPlaintext = value
            }
            try? keychain.delete()
        }
    }
}
