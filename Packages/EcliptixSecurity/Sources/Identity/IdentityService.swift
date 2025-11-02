import EcliptixCore
import Foundation

public protocol IdentityService: Sendable {

    func hasStoredIdentity(membershipId: UUID) async -> Bool

    func loadMasterKeyHandle(membershipId: UUID) async throws -> SecureMemoryHandle

    func saveMasterKey(_ masterKeyHandle: SecureMemoryHandle, membershipId: UUID) async throws

    func deleteMasterKey(membershipId: UUID) async throws

    func loadIdentityKeyBundle(membershipId: UUID) async throws -> IdentityKeyBundle?

    func saveIdentityKeyBundle(_ bundle: IdentityKeyBundle, membershipId: UUID) async throws

    func deleteAllIdentityData(membershipId: UUID) async throws

    func generateAndStoreIdentityKeys(membershipId: String, recoveryPassphrase: String?) async throws

    func hasMasterKeyHandle() async throws -> Bool
}

public struct IdentityKeyBundle: Codable {
    public let identityPublicKey: Data
    public let identityPrivateKey: Data
    public let signedPreKeyPublicKey: Data
    public let signedPreKeyPrivateKey: Data
    public let signedPreKeySignature: Data
    public let signedPreKeyId: UInt32
    public let createdAt: Date

    public init(
        identityPublicKey: Data,
        identityPrivateKey: Data,
        signedPreKeyPublicKey: Data,
        signedPreKeyPrivateKey: Data,
        signedPreKeySignature: Data,
        signedPreKeyId: UInt32,
        createdAt: Date = Date()
    ) {
        self.identityPublicKey = identityPublicKey
        self.identityPrivateKey = identityPrivateKey
        self.signedPreKeyPublicKey = signedPreKeyPublicKey
        self.signedPreKeyPrivateKey = signedPreKeyPrivateKey
        self.signedPreKeySignature = signedPreKeySignature
        self.signedPreKeyId = signedPreKeyId
        self.createdAt = createdAt
    }
}
public enum IdentityError: LocalizedError {
    case notFound(String)
    case loadFailed(String)
    case saveFailed(String)
    case deleteFailed(String)
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let message):
            return "Identity not found: \(message)"
        case .loadFailed(let message):
            return "Failed to load identity: \(message)"
        case .saveFailed(let message):
            return "Failed to save identity: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete identity: \(message)"
        case .invalidData(let message):
            return "Invalid identity data: \(message)"
        }
    }
}

public final class KeychainIdentityService: IdentityService {

    private let keychainStorage: KeychainStorage
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let masterKeyPrefix = "ecliptix.identity.masterkey"
    private let identityBundlePrefix = "ecliptix.identity.bundle"

    public init(keychainStorage: KeychainStorage = KeychainStorage()) {
        self.keychainStorage = keychainStorage
    }

    public func hasStoredIdentity(membershipId: UUID) async -> Bool {
        let masterKeyKey = makeMasterKeyKey(membershipId: membershipId)

        do {
            let data = try keychainStorage.retrieve(forKey: masterKeyKey)
            return data != nil
        } catch {
            return false
        }
    }

    public func loadMasterKeyHandle(membershipId: UUID) async throws -> SecureMemoryHandle {
        let key = makeMasterKeyKey(membershipId: membershipId)

        do {
            guard let data = try keychainStorage.retrieve(forKey: key) else {
                throw IdentityError.notFound("Master key not found for membership: \(membershipId)")
            }

            Log.info("[IdentityService] Loaded master key for membership: \(membershipId)")
            return SecureMemoryHandle(data: data)

        } catch let error as IdentityError {
            throw error
        } catch {
            throw IdentityError.loadFailed("Failed to load master key: \(error.localizedDescription)")
        }
    }

    public func saveMasterKey(_ masterKeyHandle: SecureMemoryHandle, membershipId: UUID) async throws {
        let key = makeMasterKeyKey(membershipId: membershipId)

        do {
            let data = try masterKeyHandle.readData()
            try keychainStorage.save(data, forKey: key)

            Log.info("[IdentityService] Saved master key for membership: \(membershipId)")

        } catch let error as SecureMemoryError {
            throw IdentityError.saveFailed("Secure memory error: \(error.localizedDescription)")
        } catch {
            throw IdentityError.saveFailed("Failed to save master key: \(error.localizedDescription)")
        }
    }

    public func deleteMasterKey(membershipId: UUID) async throws {
        let key = makeMasterKeyKey(membershipId: membershipId)

        do {
            try keychainStorage.delete(forKey: key)
            Log.info("[IdentityService] Deleted master key for membership: \(membershipId)")

        } catch {
            throw IdentityError.deleteFailed("Failed to delete master key: \(error.localizedDescription)")
        }
    }

    public func loadIdentityKeyBundle(membershipId: UUID) async throws -> IdentityKeyBundle? {
        let key = makeIdentityBundleKey(membershipId: membershipId)

        do {
            guard let data = try keychainStorage.retrieve(forKey: key) else {
                return nil
            }

            let bundle = try decoder.decode(IdentityKeyBundle.self, from: data)
            Log.info("[IdentityService] Loaded identity bundle for membership: \(membershipId)")
            return bundle

        } catch {
            throw IdentityError.loadFailed("Failed to load identity bundle: \(error.localizedDescription)")
        }
    }

    public func saveIdentityKeyBundle(_ bundle: IdentityKeyBundle, membershipId: UUID) async throws {
        let key = makeIdentityBundleKey(membershipId: membershipId)

        do {
            let data = try encoder.encode(bundle)
            try keychainStorage.save(data, forKey: key)

            Log.info("[IdentityService] Saved identity bundle for membership: \(membershipId)")

        } catch {
            throw IdentityError.saveFailed("Failed to save identity bundle: \(error.localizedDescription)")
        }
    }

    public func deleteAllIdentityData(membershipId: UUID) async throws {
        do {
            try await deleteMasterKey(membershipId: membershipId)
        } catch {
            Log.warning("[IdentityService] Failed to delete master key during cleanup: \(error.localizedDescription)")
        }

        do {
            let bundleKey = makeIdentityBundleKey(membershipId: membershipId)
            try keychainStorage.delete(forKey: bundleKey)
        } catch {
            Log.warning("[IdentityService] Failed to delete identity bundle during cleanup: \(error.localizedDescription)")
        }

        Log.info("[IdentityService] Deleted all identity data for membership: \(membershipId)")
    }

    private func makeMasterKeyKey(membershipId: UUID) -> String {
        return "\(masterKeyPrefix).\(membershipId.uuidString)"
    }

    private func makeIdentityBundleKey(membershipId: UUID) -> String {
        return "\(identityBundlePrefix).\(membershipId.uuidString)"
    }

    public func generateAndStoreIdentityKeys(membershipId: String, recoveryPassphrase: String?) async throws {
        Log.info("[IdentityService] Generating X3DH identity keys for membership: \(membershipId)")

        let x3dhKeyExchange = X3DHKeyExchange()

        do {
            let persistentBundle = try x3dhKeyExchange.generatePersistentKeyBundle()

            let identityBundle = IdentityKeyBundle(
                identityPublicKey: persistentBundle.identityPublicKey,
                identityPrivateKey: persistentBundle.identityPrivateKey,
                signedPreKeyPublicKey: persistentBundle.signedPreKeyPublicKey,
                signedPreKeyPrivateKey: persistentBundle.signedPreKeyPrivateKey,
                signedPreKeySignature: persistentBundle.signedPreKeySignature,
                signedPreKeyId: persistentBundle.signedPreKeyId
            )

            guard let membershipUUID = UUID(uuidString: membershipId) else {
                throw IdentityError.invalidData("Invalid membership ID format")
            }

            try await saveIdentityKeyBundle(identityBundle, membershipId: membershipUUID)

            if let passphrase = recoveryPassphrase {
                let masterKey = try deriveMasterKey(
                    identityPrivateKey: persistentBundle.identityPrivateKey,
                    passphrase: passphrase
                )

                let masterKeyHandle = SecureMemoryHandle(data: masterKey)
                try await saveMasterKey(masterKeyHandle, membershipId: membershipUUID)

                Log.info("[IdentityService] [OK] Generated and stored X3DH keys with master key for membership: \(membershipId)")
            } else {
                Log.info("[IdentityService] [OK] Generated and stored X3DH keys (without master key) for membership: \(membershipId)")
            }

        } catch {
            Log.error("[IdentityService] Failed to generate identity keys: \(error.localizedDescription)")
            throw IdentityError.saveFailed("Key generation failed: \(error.localizedDescription)")
        }
    }

    public func hasMasterKeyHandle() async throws -> Bool {

        return false
    }

    private func deriveMasterKey(identityPrivateKey: Data, passphrase: String) throws -> Data {
        let passphraseData = Data(passphrase.utf8)

        let randomSalt = try generateRandomSalt(size: 32)

        let masterKey = try HKDFKeyDerivation.deriveKey(
            inputKeyMaterial: identityPrivateKey + passphraseData,
            salt: randomSalt,
            info: Data("ecliptix-master-key-v1".utf8),
            outputByteCount: 32
        )

        Log.info("[IdentityService] Derived master key with random salt")
        return masterKey
    }

    private func generateRandomSalt(size: Int) throws -> Data {
        var salt = Data(count: size)
        let result: Int32 = salt.withUnsafeMutableBytes { buffer in
            guard let ptr = buffer.baseAddress else { return -1 }
            return SecRandomCopyBytes(kSecRandomDefault, size, ptr)
        }

        guard result == errSecSuccess else {
            throw IdentityError.saveFailed("Failed to generate random salt")
        }

        return salt
    }
}
