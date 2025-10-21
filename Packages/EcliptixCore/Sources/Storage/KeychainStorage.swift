import Foundation
import Security
import EcliptixCore

// MARK: - Keychain Storage
/// Secure storage for sensitive data using iOS Keychain
/// Migrated from: Ecliptix.Core/Infrastructure/Storage/SecureStorage.cs
@MainActor
public final class KeychainStorage {

    // MARK: - Configuration

    private let configuration: KeychainConfiguration

    // MARK: - Initialization

    public init(configuration: KeychainConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Storage Operations

    /// Stores data securely in keychain
    /// Migrated from: StoreSecureAsync()
    public func store(_ data: Data, forKey key: String) -> Result<Void, KeychainError> {
        // Create query for storing
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: configuration.accessibility
        ]

        // Add access group if specified
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Delete existing item first
        _ = delete(forKey: key)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error("[Keychain] Failed to store item for key: \(key), status: \(status)")
            return .failure(.storeFailed(status: status))
        }

        Log.debug("[Keychain] ✅ Stored item for key: \(key)")
        return .success(())
    }

    /// Stores string securely in keychain
    public func store(_ string: String, forKey key: String) -> Result<Void, KeychainError> {
        guard let data = string.data(using: .utf8) else {
            return .failure(.encodingFailed)
        }
        return store(data, forKey: key)
    }

    /// Stores Codable object securely in keychain
    public func store<T: Encodable>(_ object: T, forKey key: String) -> Result<Void, KeychainError> {
        do {
            let data = try JSONEncoder().encode(object)
            return store(data, forKey: key)
        } catch {
            Log.error("[Keychain] Failed to encode object for key: \(key), error: \(error)")
            return .failure(.encodingFailed)
        }
    }

    /// Retrieves data from keychain
    /// Migrated from: RetrieveSecureAsync()
    public func retrieve(forKey key: String) -> Result<Data, KeychainError> {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Add access group if specified
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return .failure(.notFound)
            }
            Log.error("[Keychain] Failed to retrieve item for key: \(key), status: \(status)")
            return .failure(.retrieveFailed(status: status))
        }

        guard let data = result as? Data else {
            return .failure(.invalidData)
        }

        Log.debug("[Keychain] ✅ Retrieved item for key: \(key)")
        return .success(data)
    }

    /// Retrieves string from keychain
    public func retrieveString(forKey key: String) -> Result<String, KeychainError> {
        switch retrieve(forKey: key) {
        case .success(let data):
            guard let string = String(data: data, encoding: .utf8) else {
                return .failure(.decodingFailed)
            }
            return .success(string)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Retrieves Codable object from keychain
    public func retrieve<T: Decodable>(forKey key: String) -> Result<T, KeychainError> {
        switch retrieve(forKey: key) {
        case .success(let data):
            do {
                let object = try JSONDecoder().decode(T.self, from: data)
                return .success(object)
            } catch {
                Log.error("[Keychain] Failed to decode object for key: \(key), error: \(error)")
                return .failure(.decodingFailed)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Deletes item from keychain
    /// Migrated from: DeleteSecureAsync()
    public func delete(forKey key: String) -> Result<Void, KeychainError> {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName,
            kSecAttrAccount as String: key
        ]

        // Add access group if specified
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.error("[Keychain] Failed to delete item for key: \(key), status: \(status)")
            return .failure(.deleteFailed(status: status))
        }

        Log.debug("[Keychain] 🗑️ Deleted item for key: \(key)")
        return .success(())
    }

    /// Updates existing item in keychain
    /// Migrated from: UpdateSecureAsync()
    public func update(_ data: Data, forKey key: String) -> Result<Void, KeychainError> {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName,
            kSecAttrAccount as String: key
        ]

        // Add access group if specified
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                // Item doesn't exist, store it instead
                return store(data, forKey: key)
            }
            Log.error("[Keychain] Failed to update item for key: \(key), status: \(status)")
            return .failure(.updateFailed(status: status))
        }

        Log.debug("[Keychain] ✅ Updated item for key: \(key)")
        return .success(())
    }

    /// Checks if item exists in keychain
    public func exists(forKey key: String) -> Bool {
        switch retrieve(forKey: key) {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    /// Deletes all items for this service
    /// Migrated from: ClearAllSecureAsync()
    public func deleteAll() -> Result<Void, KeychainError> {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName
        ]

        // Add access group if specified
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.error("[Keychain] Failed to delete all items, status: \(status)")
            return .failure(.deleteFailed(status: status))
        }

        Log.info("[Keychain] 🗑️ Deleted all items for service: \(configuration.serviceName)")
        return .success(())
    }

    // MARK: - Key Management

    /// Lists all keys stored in keychain for this service
    public func allKeys() -> Result<[String], KeychainError> {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        // Add access group if specified
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return .success([])
            }
            Log.error("[Keychain] Failed to list keys, status: \(status)")
            return .failure(.retrieveFailed(status: status))
        }

        guard let items = result as? [[String: Any]] else {
            return .success([])
        }

        let keys = items.compactMap { $0[kSecAttrAccount as String] as? String }
        return .success(keys)
    }
}

// MARK: - Configuration

/// Configuration for keychain storage
/// Migrated from: KeychainConfiguration.cs
public struct KeychainConfiguration {

    /// Service name for keychain items
    public let serviceName: String

    /// Access group for sharing between apps (optional)
    public let accessGroup: String?

    /// Accessibility level for keychain items
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

    // MARK: - Presets

    /// Default configuration (when unlocked, this device only)
    public static let `default` = KeychainConfiguration()

    /// After first unlock (survives reboot)
    public static let afterFirstUnlock = KeychainConfiguration(
        accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    )

    /// Always accessible (not recommended for sensitive data)
    public static let always = KeychainConfiguration(
        accessibility: kSecAttrAccessibleAlways
    )

    /// With passcode set only (most secure)
    public static let whenPasscodeSet = KeychainConfiguration(
        accessibility: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
    )
}

// MARK: - Errors

/// Keychain operation errors
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

// MARK: - Convenience Keys

/// Common keychain keys for Ecliptix app
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
