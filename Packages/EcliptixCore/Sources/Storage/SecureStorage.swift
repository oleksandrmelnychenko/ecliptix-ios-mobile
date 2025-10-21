import Foundation
import CryptoKit

// MARK: - Secure Storage
/// Encrypted local storage for sensitive application data
/// Migrated from: Ecliptix.Core/Infrastructure/Storage/EncryptedStorage.cs
@MainActor
public final class SecureStorage {

    // MARK: - Properties

    private let configuration: SecureStorageConfiguration
    private let encryptionKey: SymmetricKey
    private let fileManager = FileManager.default

    // MARK: - Initialization

    public init(configuration: SecureStorageConfiguration = .default) throws {
        self.configuration = configuration

        // Get or create encryption key from keychain
        let keychainStorage = KeychainStorage()
        let keyData: Data

        switch keychainStorage.retrieve(forKey: "ecliptix.storage.encryption_key") {
        case .success(let existingKey):
            keyData = existingKey
            Log.debug("[SecureStorage] Using existing encryption key")

        case .failure(.notFound):
            // Generate new encryption key
            let newKey = SymmetricKey(size: .bits256)
            keyData = newKey.withUnsafeBytes { Data($0) }

            // Store in keychain
            _ = keychainStorage.store(keyData, forKey: "ecliptix.storage.encryption_key")
            Log.info("[SecureStorage] Generated new encryption key")

        case .failure(let error):
            Log.error("[SecureStorage] Failed to retrieve encryption key: \(error)")
            throw SecureStorageError.keyRetrievalFailed
        }

        self.encryptionKey = SymmetricKey(data: keyData)

        // Create storage directory if needed
        try createStorageDirectoryIfNeeded()
    }

    // MARK: - Storage Operations

    /// Stores data securely with encryption
    /// Migrated from: StoreEncryptedAsync()
    public func store(_ data: Data, forKey key: String) throws {
        let filePath = fileURL(forKey: key)

        // Encrypt data
        let encryptedData = try encrypt(data)

        // Write to file
        try encryptedData.write(to: filePath, options: .atomic)

        Log.debug("[SecureStorage] ✅ Stored encrypted data for key: \(key)")
    }

    /// Stores Codable object securely
    public func store<T: Encodable>(_ object: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(object)
        try store(data, forKey: key)
    }

    /// Retrieves and decrypts data
    /// Migrated from: RetrieveEncryptedAsync()
    public func retrieve(forKey key: String) throws -> Data {
        let filePath = fileURL(forKey: key)

        // Check if file exists
        guard fileManager.fileExists(atPath: filePath.path) else {
            throw SecureStorageError.notFound
        }

        // Read encrypted data
        let encryptedData = try Data(contentsOf: filePath)

        // Decrypt data
        let decryptedData = try decrypt(encryptedData)

        Log.debug("[SecureStorage] ✅ Retrieved encrypted data for key: \(key)")
        return decryptedData
    }

    /// Retrieves Codable object
    public func retrieve<T: Decodable>(forKey key: String) throws -> T {
        let data = try retrieve(forKey: key)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Deletes stored data
    /// Migrated from: DeleteEncryptedAsync()
    public func delete(forKey key: String) throws {
        let filePath = fileURL(forKey: key)

        guard fileManager.fileExists(atPath: filePath.path) else {
            // Already deleted or doesn't exist
            return
        }

        try fileManager.removeItem(at: filePath)
        Log.debug("[SecureStorage] 🗑️ Deleted encrypted data for key: \(key)")
    }

    /// Checks if data exists
    public func exists(forKey key: String) -> Bool {
        let filePath = fileURL(forKey: key)
        return fileManager.fileExists(atPath: filePath.path)
    }

    /// Deletes all stored data
    /// Migrated from: ClearAllEncryptedAsync()
    public func deleteAll() throws {
        let storageURL = try storageDirectoryURL()

        guard fileManager.fileExists(atPath: storageURL.path) else {
            return
        }

        let contents = try fileManager.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: nil
        )

        for fileURL in contents {
            try fileManager.removeItem(at: fileURL)
        }

        Log.info("[SecureStorage] 🗑️ Deleted all encrypted data")
    }

    /// Lists all stored keys
    public func allKeys() throws -> [String] {
        let storageURL = try storageDirectoryURL()

        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: nil
        )

        return contents.map { $0.lastPathComponent }
    }

    // MARK: - Encryption

    /// Encrypts data using ChaChaPoly
    private func encrypt(_ data: Data) throws -> Data {
        do {
            let sealedBox = try ChaChaPoly.seal(data, using: encryptionKey)
            return sealedBox.combined
        } catch {
            Log.error("[SecureStorage] Encryption failed: \(error)")
            throw SecureStorageError.encryptionFailed
        }
    }

    /// Decrypts data using ChaChaPoly
    private func decrypt(_ data: Data) throws -> Data {
        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: data)
            return try ChaChaPoly.open(sealedBox, using: encryptionKey)
        } catch {
            Log.error("[SecureStorage] Decryption failed: \(error)")
            throw SecureStorageError.decryptionFailed
        }
    }

    // MARK: - File Management

    /// Returns storage directory URL
    private func storageDirectoryURL() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return documentsURL.appendingPathComponent(configuration.directoryName)
    }

    /// Returns file URL for a key
    private func fileURL(forKey key: String) -> URL {
        do {
            let storageURL = try storageDirectoryURL()
            return storageURL.appendingPathComponent(key)
        } catch {
            // Fallback - should not happen
            Log.error("[SecureStorage] Failed to get storage URL: \(error)")
            fatalError("Failed to get storage directory URL")
        }
    }

    /// Creates storage directory if it doesn't exist
    private func createStorageDirectoryIfNeeded() throws {
        let storageURL = try storageDirectoryURL()

        if !fileManager.fileExists(atPath: storageURL.path) {
            try fileManager.createDirectory(
                at: storageURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            Log.info("[SecureStorage] Created storage directory: \(storageURL.path)")
        }
    }

    // MARK: - Migration

    /// Migrates data from old key to new key
    public func migrate(from oldKey: String, to newKey: String) throws {
        guard exists(forKey: oldKey) else {
            throw SecureStorageError.notFound
        }

        let data = try retrieve(forKey: oldKey)
        try store(data, forKey: newKey)
        try delete(forKey: oldKey)

        Log.info("[SecureStorage] Migrated data from '\(oldKey)' to '\(newKey)'")
    }
}

// MARK: - Configuration

/// Configuration for secure storage
public struct SecureStorageConfiguration {

    /// Directory name for encrypted storage
    public let directoryName: String

    public init(directoryName: String = "EcliptixSecureStorage") {
        self.directoryName = directoryName
    }

    // MARK: - Presets

    /// Default configuration
    public static let `default` = SecureStorageConfiguration()
}

// MARK: - Errors

/// Secure storage errors
public enum SecureStorageError: LocalizedError {
    case keyRetrievalFailed
    case encryptionFailed
    case decryptionFailed
    case notFound
    case storeFailed
    case deleteFailed

    public var errorDescription: String? {
        switch self {
        case .keyRetrievalFailed:
            return "Failed to retrieve encryption key from keychain"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .notFound:
            return "Data not found in secure storage"
        case .storeFailed:
            return "Failed to store data"
        case .deleteFailed:
            return "Failed to delete data"
        }
    }
}

// MARK: - Convenience Keys

/// Common secure storage keys for Ecliptix app
public extension SecureStorage {
    enum Key {
        public static let userPreferences = "user_preferences.json"
        public static let cachedContacts = "cached_contacts.json"
        public static let draftMessages = "draft_messages.json"
        public static let recentSessions = "recent_sessions.json"
        public static let applicationState = "application_state.json"
    }
}
