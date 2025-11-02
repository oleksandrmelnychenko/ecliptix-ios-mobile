import CryptoKit
import Foundation

@MainActor
public final class SecureStorage {

    private let configuration: SecureStorageConfiguration
    private let encryptionKey: SymmetricKey
    private let fileManager = FileManager.default

    public init(configuration: SecureStorageConfiguration = .default) throws {
        self.configuration = configuration

        let keychainStorage = KeychainStorage()
        let keyData: Data

        do {
            keyData = try keychainStorage.retrieve(forKey: "ecliptix.storage.encryption_key")
            Log.debug("[SecureStorage] Using existing encryption key")
        } catch KeychainError.notFound {

            let newKey = SymmetricKey(size: .bits256)
            keyData = newKey.withUnsafeBytes { Data($0) }

            try keychainStorage.store(keyData, forKey: "ecliptix.storage.encryption_key")
            Log.info("[SecureStorage] Generated new encryption key")
        } catch {
            Log.error("[SecureStorage] Failed to retrieve encryption key: \(error)")
            throw SecureStorageError.keyRetrievalFailed
        }

        self.encryptionKey = SymmetricKey(data: keyData)

        try createStorageDirectoryIfNeeded()
    }

    public func store(_ data: Data, forKey key: String) throws {
        let filePath = fileURL(forKey: key)

        let encryptedData = try encrypt(data)

        try encryptedData.write(to: filePath, options: .atomic)

        Log.debug("[SecureStorage] [OK] Stored encrypted data for key: \(key)")
    }

    public func store<T: Encodable>(_ object: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(object)
        try store(data, forKey: key)
    }

    public func retrieve(forKey key: String) throws -> Data {
        let filePath = fileURL(forKey: key)

        guard fileManager.fileExists(atPath: filePath.path) else {
            throw SecureStorageError.notFound
        }

        let encryptedData = try Data(contentsOf: filePath)

        let decryptedData = try decrypt(encryptedData)

        Log.debug("[SecureStorage] [OK] Retrieved encrypted data for key: \(key)")
        return decryptedData
    }

    public func retrieve<T: Decodable>(forKey key: String) throws -> T {
        let data = try retrieve(forKey: key)
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func delete(forKey key: String) throws {
        let filePath = fileURL(forKey: key)

        guard fileManager.fileExists(atPath: filePath.path) else {

            return
        }

        try fileManager.removeItem(at: filePath)
        Log.debug("[SecureStorage]  Deleted encrypted data for key: \(key)")
    }

    public func exists(forKey key: String) -> Bool {
        let filePath = fileURL(forKey: key)
        return fileManager.fileExists(atPath: filePath.path)
    }

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

        Log.info("[SecureStorage]  Deleted all encrypted data")
    }

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

    private func encrypt(_ data: Data) throws -> Data {
        do {
            let sealedBox = try ChaChaPoly.seal(data, using: encryptionKey)
            return sealedBox.combined
        } catch {
            Log.error("[SecureStorage] Encryption failed: \(error)")
            throw SecureStorageError.encryptionFailed
        }
    }

    private func decrypt(_ data: Data) throws -> Data {
        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: data)
            return try ChaChaPoly.open(sealedBox, using: encryptionKey)
        } catch {
            Log.error("[SecureStorage] Decryption failed: \(error)")
            throw SecureStorageError.decryptionFailed
        }
    }

    private func storageDirectoryURL() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return documentsURL.appendingPathComponent(configuration.directoryName)
    }

    private func fileURL(forKey key: String) -> URL {
        do {
            let storageURL = try storageDirectoryURL()
            return storageURL.appendingPathComponent(key)
        } catch {

            Log.error("[SecureStorage] Failed to get storage URL: \(error)")
            fatalError("Failed to get storage directory URL")
        }
    }

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

public struct SecureStorageConfiguration: Sendable {

    public let directoryName: String

    public init(directoryName: String = "EcliptixSecureStorage") {
        self.directoryName = directoryName
    }

    public static let `default` = SecureStorageConfiguration()
}

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

public extension SecureStorage {
    enum Key {
        public static let userPreferences = "user_preferences.json"
        public static let cachedContacts = "cached_contacts.json"
        public static let draftMessages = "draft_messages.json"
        public static let recentSessions = "recent_sessions.json"
        public static let applicationState = "application_state.json"
    }
}
