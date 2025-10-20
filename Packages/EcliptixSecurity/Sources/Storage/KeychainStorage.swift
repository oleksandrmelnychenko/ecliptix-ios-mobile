import Foundation
import Security
import EcliptixCore

// MARK: - Keychain Storage Implementation
/// Provides secure storage using iOS Keychain Services
public final class KeychainStorage {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "com.ecliptix.keychain", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Save to Keychain
    public func save(_ data: Data, forKey key: String) throws {
        // Delete existing item if present
        _ = try? delete(forKey: key)

        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw SecurityError.keychainError(status: status)
        }
    }

    // MARK: - Retrieve from Keychain
    public func retrieve(forKey key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SecurityError.keychainError(status: status)
        }

        guard let data = result as? Data else {
            throw SecurityError.invalidData
        }

        return data
    }

    // MARK: - Delete from Keychain
    public func delete(forKey key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityError.keychainError(status: status)
        }
    }

    // MARK: - Check if Key Exists
    public func exists(forKey key: String) -> Bool {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Base Query
    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}

// MARK: - SecureStorage Protocol Conformance
extension KeychainStorage: SecureStorage {
    public func save<T: Codable>(_ value: T, forKey key: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        try save(data, forKey: key)
    }

    public func retrieve<T: Codable>(forKey key: String, as type: T.Type) throws -> T? {
        guard let data = try retrieve(forKey: key) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}
