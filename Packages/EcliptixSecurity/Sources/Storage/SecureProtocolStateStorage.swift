import Crypto
import EcliptixCore
import Foundation

public protocol SecureProtocolStateStorage: Sendable {

    func loadState(connectId: String, membershipId: UUID) async throws -> Data?

    func saveState(_ state: Data, connectId: String, membershipId: UUID) async throws

    func deleteState(connectId: String, membershipId: UUID) async throws

    func deleteAllStates(membershipId: UUID) async throws
}

public final class SecureProtocolStateKeychainStorage: SecureProtocolStateStorage {

    private let keychainStorage: KeychainStorage
    private let encryptionService: AESGCMCrypto

    public init(
        keychainStorage: KeychainStorage = KeychainStorage(),
        encryptionService: AESGCMCrypto = AESGCMCrypto()
    ) {
        self.keychainStorage = keychainStorage
        self.encryptionService = encryptionService
    }

    public func loadState(connectId: String, membershipId: UUID) async throws -> Data? {
        let storageKey = makeKey(connectId: connectId, membershipId: membershipId)

        do {

            guard let encryptedData = try keychainStorage.retrieve(forKey: storageKey) else {
                Log.debug("[ProtocolStateStorage] No state found for connectId: \(connectId)")
                return nil
            }

            let encryptionKey = try deriveEncryptionKey(membershipId: membershipId)

            let decryptedState = try encryptionService.decrypt(
                data: encryptedData,
                key: encryptionKey
            )

            Log.info("[ProtocolStateStorage] [OK] Loaded and decrypted state for connectId: \(connectId), size: \(decryptedState.count) bytes")
            return decryptedState

        } catch {
            Log.error("[ProtocolStateStorage] Failed to load state: \(error.localizedDescription)")
            throw ProtocolStateStorageError.loadFailed(error.localizedDescription)
        }
    }

    public func saveState(_ state: Data, connectId: String, membershipId: UUID) async throws {
        let storageKey = makeKey(connectId: connectId, membershipId: membershipId)

        do {

            let encryptionKey = try deriveEncryptionKey(membershipId: membershipId)

            let encryptedState = try encryptionService.encrypt(
                data: state,
                key: encryptionKey
            )

            try keychainStorage.save(encryptedState, forKey: storageKey)

            Log.info("[ProtocolStateStorage] [OK] Encrypted and saved state for connectId: \(connectId), plaintext: \(state.count) bytes, encrypted: \(encryptedState.count) bytes")

        } catch {
            Log.error("[ProtocolStateStorage] Failed to save state: \(error.localizedDescription)")
            throw ProtocolStateStorageError.saveFailed(error.localizedDescription)
        }
    }

    public func deleteState(connectId: String, membershipId: UUID) async throws {
        let key = makeKey(connectId: connectId, membershipId: membershipId)

        do {
            try keychainStorage.delete(forKey: key)
            Log.info("[ProtocolStateStorage] Deleted state for connectId: \(connectId)")

        } catch {
            Log.warning("[ProtocolStateStorage] Failed to delete state: \(error.localizedDescription)")
            throw ProtocolStateStorageError.deleteFailed(error.localizedDescription)
        }
    }

    public func deleteAllStates(membershipId: UUID) async throws {

        Log.warning("[ProtocolStateStorage] deleteAllStates not fully implemented - requires index maintenance")
        throw ProtocolStateStorageError.deleteFailed("Bulk deletion not supported without index")
    }

    enum ProtocolStateStorageError: LocalizedError {
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

        let salt = Data("ecliptix-protocol-state-encryption".utf8)
        let info = Data("state-encryption-key-v1".utf8)

        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: membershipIdData),
            salt: salt,
            info: info,
            outputByteCount: 32
        )

        return derivedKey
    }

    private func makeKey(connectId: String, membershipId: UUID) -> String {
        return "ecliptix.protocol.state.\(membershipId.uuidString).\(connectId)"
    }
}
