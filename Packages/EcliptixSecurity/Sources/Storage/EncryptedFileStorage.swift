import Foundation
import Crypto
import EcliptixCore

// MARK: - Encrypted File Storage
/// Provides encrypted file-based storage with iOS Data Protection
public final class EncryptedFileStorage {
    private let storagePath: URL
    private let encryptionKey: SymmetricKey

    public init(storagePath: URL? = nil, encryptionKey: SymmetricKey? = nil) throws {
        // Use Application Support directory by default
        if let storagePath = storagePath {
            self.storagePath = storagePath
        } else {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.storagePath = appSupport.appendingPathComponent("SecureStorage", isDirectory: true)
        }

        // Generate or use provided encryption key
        if let key = encryptionKey {
            self.encryptionKey = key
        } else {
            // For persistent encryption, key should be stored in Keychain
            self.encryptionKey = SymmetricKey(size: .bits256)
        }

        try initializeStorageDirectory()
    }

    // MARK: - Store Data
    public func store(_ data: Data, forKey key: String) throws {
        let filePath = try getHashedFilePath(for: key)

        // Encrypt data using ChaChaPoly
        let sealedBox = try ChaChaPoly.seal(data, using: encryptionKey)

        // Combine nonce + ciphertext + tag
        var encryptedData = Data()
        encryptedData.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        encryptedData.append(sealedBox.ciphertext)
        encryptedData.append(sealedBox.tag)

        // Write to file with complete data protection
        try encryptedData.write(
            to: filePath,
            options: [.atomic, .completeFileProtection]
        )
    }

    // MARK: - Retrieve Data
    public func retrieve(forKey key: String) throws -> Data? {
        let filePath = try getHashedFilePath(for: key)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        let encryptedData = try Data(contentsOf: filePath)

        guard encryptedData.count > 12 + 16 else {
            // Too small to contain nonce (12) + tag (16)
            return nil
        }

        // Extract nonce (12 bytes), ciphertext, and tag (16 bytes)
        let nonce = try ChaChaPoly.Nonce(data: encryptedData.prefix(12))
        let tag = encryptedData.suffix(16)
        let ciphertext = encryptedData.dropFirst(12).dropLast(16)

        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        // Decrypt
        let decryptedData = try ChaChaPoly.open(sealedBox, using: encryptionKey)
        return decryptedData
    }

    // MARK: - Delete Data
    public func delete(forKey key: String) throws {
        let filePath = try getHashedFilePath(for: key)

        if FileManager.default.fileExists(atPath: filePath.path) {
            try FileManager.default.removeItem(at: filePath)
        }
    }

    // MARK: - Check if Key Exists
    public func exists(forKey key: String) -> Bool {
        guard let filePath = try? getHashedFilePath(for: key) else {
            return false
        }
        return FileManager.default.fileExists(atPath: filePath.path)
    }

    // MARK: - Get Hashed File Path
    private func getHashedFilePath(for key: String) throws -> URL {
        guard let keyData = key.data(using: .utf8) else {
            throw SecurityError.invalidData
        }

        let hash = SHA256.hash(data: keyData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return storagePath.appendingPathComponent("\(hashString).enc")
    }

    // MARK: - Initialize Storage Directory
    private func initializeStorageDirectory() throws {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: storagePath.path) {
            try fileManager.createDirectory(
                at: storagePath,
                withIntermediateDirectories: true,
                attributes: [
                    FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            )
        }
    }
}
