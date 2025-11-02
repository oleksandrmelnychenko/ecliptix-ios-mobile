import Crypto
import EcliptixCore
import Foundation

public final class EncryptedFileStorage {
    private let storagePath: URL
    private let encryptionKey: SymmetricKey
    private let keychainStorage: KeychainStorage

    private static let masterKeyKeychainKey = "ecliptix.encrypted.file.storage.master.key"

    public init(
        storagePath: URL? = nil,
        encryptionKey: SymmetricKey? = nil,
        keychainStorage: KeychainStorage = KeychainStorage()
    ) throws {

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

        self.keychainStorage = keychainStorage

        if let key = encryptionKey {

            self.encryptionKey = key
        } else {

            self.encryptionKey = try Self.loadOrGenerateMasterKey(keychainStorage: keychainStorage)
        }

        try initializeStorageDirectory()
    }

    private static func loadOrGenerateMasterKey(keychainStorage: KeychainStorage) throws -> SymmetricKey {

        if let existingKeyData = try keychainStorage.retrieve(forKey: masterKeyKeychainKey) {
            Log.info("[EncryptedFileStorage] Loaded existing master encryption key from Keychain")
            return SymmetricKey(data: existingKeyData)
        }

        let newKey = SymmetricKey(size: .bits256)

        let keyData = newKey.withUnsafeBytes { Data($0) }
        try keychainStorage.save(keyData, forKey: masterKeyKeychainKey)

        Log.info("[EncryptedFileStorage] Generated and stored new master encryption key in Keychain")
        return newKey
    }
    public func store(_ data: Data, forKey key: String) throws {
        let filePath = try getHashedFilePath(for: key)

        let sealedBox = try ChaChaPoly.seal(data, using: encryptionKey)

        var encryptedData = Data()
        encryptedData.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        encryptedData.append(sealedBox.ciphertext)
        encryptedData.append(sealedBox.tag)

        try encryptedData.write(
            to: filePath,
            options: [.atomic, .completeFileProtection]
        )
    }
    public func retrieve(forKey key: String) throws -> Data? {
        let filePath = try getHashedFilePath(for: key)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        let encryptedData = try Data(contentsOf: filePath)

        guard encryptedData.count > 12 + 16 else {

            return nil
        }

        let nonce = try ChaChaPoly.Nonce(data: encryptedData.prefix(12))
        let tag = encryptedData.suffix(16)
        let ciphertext = encryptedData.dropFirst(12).dropLast(16)

        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        let decryptedData = try ChaChaPoly.open(sealedBox, using: encryptionKey)
        return decryptedData
    }
    public func delete(forKey key: String) throws {
        let filePath = try getHashedFilePath(for: key)

        if FileManager.default.fileExists(atPath: filePath.path) {
            try FileManager.default.removeItem(at: filePath)
        }
    }
    public func exists(forKey key: String) -> Bool {
        guard let filePath = try? getHashedFilePath(for: key) else {
            return false
        }
        return FileManager.default.fileExists(atPath: filePath.path)
    }
    private func getHashedFilePath(for key: String) throws -> URL {
        guard let keyData = key.data(using: .utf8) else {
            throw SecurityError.invalidData
        }

        let hash = SHA256.hash(data: keyData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return storagePath.appendingPathComponent("\(hashString).enc")
    }
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
