import Crypto
import EcliptixCore
import Foundation

public protocol SkippedMessageKeysStorage {

    func loadKeys(connectId: String, membershipId: UUID) async throws -> [UInt32: Data]

    func saveKeys(_ keys: [UInt32: Data], connectId: String, membershipId: UUID) async throws

    func deleteKeys(connectId: String, membershipId: UUID) async throws

    func deleteAllKeys(membershipId: UUID) async throws
}

private struct SkippedKeysContainer: Codable {
    let keys: [UInt32: Data]
    let timestamp: Date
    let version: Int

    init(keys: [UInt32: Data]) {
        self.keys = keys
        self.timestamp = Date()
        self.version = 1
    }
}

public final class SkippedMessageKeysKeychainStorage: SkippedMessageKeysStorage {

    private let keychainStorage: KeychainStorage
    private let encryptionService: AESGCMCrypto

    public init(
        keychainStorage: KeychainStorage = KeychainStorage(),
        encryptionService: AESGCMCrypto = AESGCMCrypto()
    ) {
        self.keychainStorage = keychainStorage
        self.encryptionService = encryptionService
    }

    public func loadKeys(connectId: String, membershipId: UUID) async throws -> [UInt32: Data] {
        let storageKey = makeStorageKey(connectId: connectId, membershipId: membershipId)

        do {

            guard let encryptedData = try keychainStorage.retrieve(forKey: storageKey) else {
                Log.debug("[SkippedKeysStorage] No skipped keys found for connectId: \(connectId)")
                return [:]
            }

            let encryptionKey = try deriveEncryptionKey(membershipId: membershipId)

            let decryptedData = try encryptionService.decrypt(
                data: encryptedData,
                key: encryptionKey
            )

            let decoder = JSONDecoder()
            let container = try decoder.decode(SkippedKeysContainer.self, from: decryptedData)

            Log.info("[SkippedKeysStorage] [OK] Loaded \(container.keys.count) skipped keys for connectId: \(connectId)")
            return container.keys

        } catch {
            Log.error("[SkippedKeysStorage] Failed to load skipped keys: \(error.localizedDescription)")
            throw SkippedKeysStorageError.loadFailed(error.localizedDescription)
        }
    }

    public func saveKeys(_ keys: [UInt32: Data], connectId: String, membershipId: UUID) async throws {
        let storageKey = makeStorageKey(connectId: connectId, membershipId: membershipId)

        do {

            let container = SkippedKeysContainer(keys: keys)
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(container)

            let encryptionKey = try deriveEncryptionKey(membershipId: membershipId)

            let encryptedData = try encryptionService.encrypt(
                data: jsonData,
                key: encryptionKey
            )

            try keychainStorage.save(encryptedData, forKey: storageKey)

            Log.info("[SkippedKeysStorage] [OK] Saved \(keys.count) skipped keys for connectId: \(connectId)")

        } catch {
            Log.error("[SkippedKeysStorage] Failed to save skipped keys: \(error.localizedDescription)")
            throw SkippedKeysStorageError.saveFailed(error.localizedDescription)
        }
    }

    public func deleteKeys(connectId: String, membershipId: UUID) async throws {
        let storageKey = makeStorageKey(connectId: connectId, membershipId: membershipId)

        do {
            try keychainStorage.delete(forKey: storageKey)
            Log.info("[SkippedKeysStorage] Deleted skipped keys for connectId: \(connectId)")

        } catch {
            Log.warning("[SkippedKeysStorage] Failed to delete skipped keys: \(error.localizedDescription)")
            throw SkippedKeysStorageError.deleteFailed(error.localizedDescription)
        }
    }

    public func deleteAllKeys(membershipId: UUID) async throws {

        Log.warning("[SkippedKeysStorage] deleteAllKeys not fully implemented - requires index maintenance")
        throw SkippedKeysStorageError.deleteFailed("Bulk deletion not supported without index")
    }

    enum SkippedKeysStorageError: LocalizedError {
        case loadFailed(String)
        case saveFailed(String)
        case deleteFailed(String)

        var errorDescription: String? {
            switch self {
            case .loadFailed(let msg):
                return "Load failed: \(msg)"
            case .saveFailed(let msg):
                return "Save failed: \(msg)"
            case .deleteFailed(let msg):
                return "Delete failed: \(msg)"
            }
        }
    }

    private func deriveEncryptionKey(membershipId: UUID) throws -> SymmetricKey {

        var uuidBytes = membershipId.uuid
        let membershipIdData = withUnsafeBytes(of: &uuidBytes) { Data($0) }

        let salt = Data("ecliptix-skipped-keys-encryption".utf8)
        let info = Data("skipped-keys-encryption-key-v1".utf8)

        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: membershipIdData),
            salt: salt,
            info: info,
            outputByteCount: 32
        )

        return derivedKey
    }

    private func makeStorageKey(connectId: String, membershipId: UUID) -> String {
        return "ecliptix.skipped.keys.\(membershipId.uuidString).\(connectId)"
    }
}
