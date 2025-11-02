import Foundation
@preconcurrency import Security
@preconcurrency import CoreFoundation

public final class KeychainStorage: @unchecked Sendable {

    private let configuration: KeychainConfiguration

    public init(configuration: KeychainConfiguration = .default) {
        self.configuration = configuration
    }

    public func store(_ data: Data, forKey key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: configuration.accessibility
        ]

        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        try? delete(forKey: key)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error("[Keychain] Failed to store item for key: \(key), status: \(status)")
            throw KeychainError.storeFailed(status: status)
        }

        Log.debug("[Keychain] [OK] Stored item for key: \(key)")
    }

    public func store(_ string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try store(data, forKey: key)
    }

    public func store<T: Encodable>(_ object: T, forKey key: String) throws {
        do {
            let data = try JSONEncoder().encode(object)
            try store(data, forKey: key)
        } catch let error as KeychainError {
            throw error
        } catch {
            Log.error("[Keychain] Failed to encode object for key: \(key), error: \(error)")
            throw KeychainError.encodingFailed
        }
    }

    public func retrieve(forKey key: String) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            Log.error("[Keychain] Failed to retrieve item for key: \(key), status: \(status)")
            throw KeychainError.retrieveFailed(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        Log.debug("[Keychain] [OK] Retrieved item for key: \(key)")
        return data
    }

    public func retrieveString(forKey key: String) throws -> String {
        let data = try retrieve(forKey: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    public func retrieve<T: Decodable>(forKey key: String) throws -> T {
        let data = try retrieve(forKey: key)
        do {
            let object = try JSONDecoder().decode(T.self, from: data)
            return object
        } catch {
            Log.error("[Keychain] Failed to decode object for key: \(key), error: \(error)")
            throw KeychainError.decodingFailed
        }
    }

    public func delete(forKey key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName,
            kSecAttrAccount as String: key
        ]

        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.error("[Keychain] Failed to delete item for key: \(key), status: \(status)")
            throw KeychainError.deleteFailed(status: status)
        }

        Log.debug("[Keychain]  Deleted item for key: \(key)")
    }

    public func update(_ data: Data, forKey key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName,
            kSecAttrAccount as String: key
        ]

        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {

                try store(data, forKey: key)
                return
            }
            Log.error("[Keychain] Failed to update item for key: \(key), status: \(status)")
            throw KeychainError.updateFailed(status: status)
        }

        Log.debug("[Keychain] [OK] Updated item for key: \(key)")
    }

    public func exists(forKey key: String) -> Bool {
        do {
            _ = try retrieve(forKey: key)
            return true
        } catch {
            return false
        }
    }

    public func deleteAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName
        ]

        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.error("[Keychain] Failed to delete all items, status: \(status)")
            throw KeychainError.deleteFailed(status: status)
        }

        Log.info("[Keychain]  Deleted all items for service: \(configuration.serviceName)")
    }

    public func allKeys() throws -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return []
            }
            Log.error("[Keychain] Failed to list keys, status: \(status)")
            throw KeychainError.retrieveFailed(status: status)
        }

        guard let items = result as? [[String: Any]] else {
            return []
        }

        let keys = items.compactMap { $0[kSecAttrAccount as String] as? String }
        return keys
    }
}

public struct KeychainConfiguration: @unchecked Sendable {

    public let serviceName: String

    public let accessGroup: String?

    public let accessibility: CFString

    public init(
        serviceName: String = "com.ecliptix.ios",
        accessGroup: String? = nil,
        accessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
        self.accessibility = accessibility
    }

    public static let `default` = KeychainConfiguration()

    @available(*, deprecated, message: "Use default configuration for better security")
    public static let afterFirstUnlock = KeychainConfiguration(
        accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    )

    public static let whenPasscodeSet = KeychainConfiguration(
        accessibility: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
    )
}

public enum KeychainError: LocalizedError {
    case storeFailed(status: OSStatus)
    case retrieveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case updateFailed(status: OSStatus)
    case notFound
    case invalidData
    case encodingFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Failed to store item in keychain (status: \(status))"
        case .retrieveFailed(let status):
            return "Failed to retrieve item from keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete item from keychain (status: \(status))"
        case .updateFailed(let status):
            return "Failed to update item in keychain (status: \(status))"
        case .notFound:
            return "Item not found in keychain"
        case .invalidData:
            return "Invalid data retrieved from keychain"
        case .encodingFailed:
            return "Failed to encode data for keychain"
        case .decodingFailed:
            return "Failed to decode data from keychain"
        }
    }
}

public extension KeychainStorage {
    enum Key {
        public static let identityKeys = "ecliptix.identity.keys"
        public static let sessionState = "ecliptix.session.state"
        public static let secureKey = "ecliptix.auth.secure_key"
        public static let deviceId = "ecliptix.device.id"
        public static let membershipId = "ecliptix.membership.id"
        public static let refreshToken = "ecliptix.auth.refresh_token"
        public static let biometricKey = "ecliptix.auth.biometric_key"
    }
}
