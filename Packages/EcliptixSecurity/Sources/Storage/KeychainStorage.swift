import EcliptixCore
import Foundation
import Security

public final class KeychainStorage: @unchecked Sendable {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "com.ecliptix.keychain", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }
    public func save(_ data: Data, forKey key: String) throws {

        _ = try? delete(forKey: key)

        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw SecurityError.keychainError(status: status)
        }
    }
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
    public func delete(forKey key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityError.keychainError(status: status)
        }
    }
    public func exists(forKey key: String) -> Bool {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
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
