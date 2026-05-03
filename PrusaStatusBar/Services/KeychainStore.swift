import Foundation
import Security

/// Protocol for the API-key store. Production uses `SystemKeychainStore`; tests
/// substitute `InMemoryKeychainStore`.
public protocol KeychainStore: Sendable {
    func read() -> String?
    func write(_ value: String) throws
    func delete() throws
}

public enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}

/// Stores a single value (`account = "prusalink-api-key"`,
/// `service = bundleId`) as a generic Keychain password. Per spec, the API key
/// must never be written to `UserDefaults` or plaintext files.
public struct SystemKeychainStore: KeychainStore {
    private let service: String
    private let account: String

    public init(
        service: String? = nil,
        account: String = "prusalink-api-key"
    ) {
        self.service = service ?? Bundle.main.bundleIdentifier ?? "com.deimosfr.prusastatusbar"
        self.account = account
    }

    public func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            Log.keychain.error("Keychain read failed: OSStatus \(status, privacy: .public)")
            return nil
        }
    }

    public func write(_ value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unhandled(errSecParam)
        }
        var query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // No existing item, fall through to add.
            break
        default:
            throw KeychainError.unhandled(updateStatus)
        }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandled(addStatus)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unhandled(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

/// In-memory implementation for tests and prototype mode.
public final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
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
        self.value = value
    }

    public func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        value = nil
    }
}
