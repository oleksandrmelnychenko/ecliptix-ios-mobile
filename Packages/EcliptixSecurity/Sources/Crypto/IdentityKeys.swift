import Foundation
import Crypto
import CryptoKit
import EcliptixCore

// MARK: - One Time Pre Key
/// Local one-time pre-key with private and public key
public final class OneTimePreKey {
    public let preKeyId: UInt32
    private var privateKey: Data
    public let publicKey: Data
    private var isDisposed = false

    public init(preKeyId: UInt32, privateKey: Data, publicKey: Data) {
        self.preKeyId = preKeyId
        self.privateKey = privateKey
        self.publicKey = publicKey
    }

    deinit {
        dispose()
    }

    public static func generate(preKeyId: UInt32) -> Result<OneTimePreKey, ProtocolFailure> {
        let x25519 = X25519KeyExchange()
        let (privateKey, publicKey) = x25519.generateKeyPair()
        let privateKeyBytes = x25519.privateKeyToBytes(privateKey)
        let publicKeyBytes = x25519.publicKeyToBytes(publicKey)

        return .success(OneTimePreKey(
            preKeyId: preKeyId,
            privateKey: privateKeyBytes,
            publicKey: publicKeyBytes
        ))
    }

    public func getPrivateKey() -> Data? {
        guard !isDisposed else { return nil }
        return Data(privateKey)
    }

    public func getPublicKey() -> Data {
        return Data(publicKey)
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        CryptographicHelpers.secureWipe(&privateKey)
    }
}

// MARK: - Identity Keys
/// Manages identity keys for X3DH key agreement and signing
/// Migrated from: Ecliptix.Protocol.System.Core.EcliptixSystemIdentityKeys.cs (1053 lines)
public final class IdentityKeys {

    // MARK: - Properties

    // Ed25519 keys (for signing)
    private var ed25519SecretKey: Data
    public let ed25519PublicKey: Data

    // X25519 identity keys
    private var identityX25519SecretKey: Data
    public let identityX25519PublicKey: Data

    // Signed pre-key
    public let signedPreKeyId: UInt32
    private var signedPreKeySecret: Data
    public let signedPreKeyPublic: Data
    public let signedPreKeySignature: Data

    // One-time pre-keys
    private var oneTimePreKeys: [OneTimePreKey]

    // Ephemeral key (for X3DH)
    private var ephemeralSecretKey: Data?
    private var ephemeralPublicKey: Data?

    private var isDisposed = false
    private let lock = NSLock()

    // MARK: - Initialization

    private init(
        ed25519SecretKey: Data,
        ed25519PublicKey: Data,
        identityX25519SecretKey: Data,
        identityX25519PublicKey: Data,
        signedPreKeyId: UInt32,
        signedPreKeySecret: Data,
        signedPreKeyPublic: Data,
        signedPreKeySignature: Data,
        oneTimePreKeys: [OneTimePreKey]
    ) {
        self.ed25519SecretKey = ed25519SecretKey
        self.ed25519PublicKey = ed25519PublicKey
        self.identityX25519SecretKey = identityX25519SecretKey
        self.identityX25519PublicKey = identityX25519PublicKey
        self.signedPreKeyId = signedPreKeyId
        self.signedPreKeySecret = signedPreKeySecret
        self.signedPreKeyPublic = signedPreKeyPublic
        self.signedPreKeySignature = signedPreKeySignature
        self.oneTimePreKeys = oneTimePreKeys
    }

    deinit {
        dispose()
    }

    // MARK: - Create

    /// Creates new identity keys with specified number of one-time pre-keys
    /// Migrated from: EcliptixSystemIdentityKeys.Create()
    public static func create(oneTimeKeyCount: UInt32 = 100) -> Result<IdentityKeys, ProtocolFailure> {
        guard oneTimeKeyCount <= Int32.max else {
            return .failure(.generic("One-time key count exceeds limits"))
        }

        // Generate Ed25519 signing key pair
        let ed25519PrivateKey = Curve25519.Signing.PrivateKey()
        let ed25519SecretKeyBytes = ed25519PrivateKey.rawRepresentation
        let ed25519PublicKeyBytes = ed25519PrivateKey.publicKey.rawRepresentation

        // Generate X25519 identity key pair
        let x25519 = X25519KeyExchange()
        let (identityPrivateKey, identityPublicKey) = x25519.generateKeyPair()
        let identityPrivateKeyBytes = x25519.privateKeyToBytes(identityPrivateKey)
        let identityPublicKeyBytes = x25519.publicKeyToBytes(identityPublicKey)

        // Generate signed pre-key
        let signedPreKeyId = UInt32.random(in: 1...UInt32.max)
        let (spkPrivateKey, spkPublicKey) = x25519.generateKeyPair()
        let spkPrivateKeyBytes = x25519.privateKeyToBytes(spkPrivateKey)
        let spkPublicKeyBytes = x25519.publicKeyToBytes(spkPublicKey)

        // Sign the pre-key with Ed25519
        guard let signatureBytes = try? ed25519PrivateKey.signature(for: spkPublicKeyBytes) else {
            return .failure(.generic("Failed to sign pre-key"))
        }

        // Generate one-time pre-keys
        var oneTimePreKeys: [OneTimePreKey] = []
        var usedIds = Set<UInt32>()
        var idCounter: UInt32 = 2

        for _ in 0..<oneTimeKeyCount {
            var id = idCounter
            idCounter += 1

            while usedIds.contains(id) {
                id = UInt32.random(in: 1...UInt32.max)
            }
            usedIds.insert(id)

            guard case .success(let opk) = OneTimePreKey.generate(preKeyId: id) else {
                // Clean up on failure
                for key in oneTimePreKeys {
                    key.dispose()
                }
                return .failure(.generic("Failed to generate one-time pre-key"))
            }

            oneTimePreKeys.append(opk)
        }

        let keys = IdentityKeys(
            ed25519SecretKey: Data(ed25519SecretKeyBytes),
            ed25519PublicKey: Data(ed25519PublicKeyBytes),
            identityX25519SecretKey: identityPrivateKeyBytes,
            identityX25519PublicKey: identityPublicKeyBytes,
            signedPreKeyId: signedPreKeyId,
            signedPreKeySecret: spkPrivateKeyBytes,
            signedPreKeyPublic: spkPublicKeyBytes,
            signedPreKeySignature: Data(signatureBytes),
            oneTimePreKeys: oneTimePreKeys
        )

        return .success(keys)
    }

    // MARK: - Create from Master Key

    /// Creates identity keys derived from a master key
    /// Migrated from: CreateFromMasterKey()
    public static func createFromMasterKey(
        masterKey: Data,
        membershipId: String,
        oneTimeKeyCount: UInt32 = 100
    ) -> Result<IdentityKeys, ProtocolFailure> {

        // Derive Ed25519 seed from master key
        let ed25519Info = Data("ecliptix-ed25519-\(membershipId)".utf8)
        guard let ed25519Seed = try? HKDFKeyDerivation.deriveKey(
            inputKeyMaterial: masterKey,
            salt: nil,
            info: ed25519Info,
            outputByteCount: 32
        ) else {
            return .failure(.generic("Failed to derive Ed25519 seed"))
        }

        // Generate Ed25519 key pair from seed
        guard let ed25519PrivateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: ed25519Seed) else {
            return .failure(.generic("Failed to create Ed25519 key from seed"))
        }
        let ed25519SecretKeyBytes = ed25519PrivateKey.rawRepresentation
        let ed25519PublicKeyBytes = ed25519PrivateKey.publicKey.rawRepresentation

        // Derive X25519 seed from master key
        let x25519Info = Data("ecliptix-x25519-\(membershipId)".utf8)
        guard let x25519Seed = try? HKDFKeyDerivation.deriveKey(
            inputKeyMaterial: masterKey,
            salt: nil,
            info: x25519Info,
            outputByteCount: 32
        ) else {
            return .failure(.generic("Failed to derive X25519 seed"))
        }

        // Generate X25519 key pair from seed
        let x25519 = X25519KeyExchange()
        guard let identityPrivateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: x25519Seed) else {
            return .failure(.generic("Failed to create X25519 key from seed"))
        }
        let identityPrivateKeyBytes = x25519.privateKeyToBytes(identityPrivateKey)
        let identityPublicKeyBytes = x25519.publicKeyToBytes(identityPrivateKey.publicKey)

        // Derive signed pre-key seed
        let spkInfo = Data("ecliptix-spk-\(membershipId)".utf8)
        guard let spkSeed = try? HKDFKeyDerivation.deriveKey(
            inputKeyMaterial: masterKey,
            salt: nil,
            info: spkInfo,
            outputByteCount: 36  // 4 bytes for ID + 32 bytes for key
        ) else {
            return .failure(.generic("Failed to derive signed pre-key seed"))
        }

        // Extract ID and key material
        let signedPreKeyId = spkSeed.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let spkKeyMaterial = spkSeed.suffix(32)

        guard let spkPrivateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: spkKeyMaterial) else {
            return .failure(.generic("Failed to create signed pre-key from seed"))
        }
        let spkPrivateKeyBytes = x25519.privateKeyToBytes(spkPrivateKey)
        let spkPublicKeyBytes = x25519.publicKeyToBytes(spkPrivateKey.publicKey)

        // Sign the pre-key
        guard let signatureBytes = try? ed25519PrivateKey.signature(for: spkPublicKeyBytes) else {
            return .failure(.generic("Failed to sign pre-key"))
        }

        // Generate one-time pre-keys (randomly generated, not derived)
        var oneTimePreKeys: [OneTimePreKey] = []
        for i in 0..<oneTimeKeyCount {
            guard case .success(let opk) = OneTimePreKey.generate(preKeyId: UInt32(i + 2)) else {
                for key in oneTimePreKeys {
                    key.dispose()
                }
                return .failure(.generic("Failed to generate one-time pre-key"))
            }
            oneTimePreKeys.append(opk)
        }

        let keys = IdentityKeys(
            ed25519SecretKey: Data(ed25519SecretKeyBytes),
            ed25519PublicKey: Data(ed25519PublicKeyBytes),
            identityX25519SecretKey: identityPrivateKeyBytes,
            identityX25519PublicKey: identityPublicKeyBytes,
            signedPreKeyId: signedPreKeyId,
            signedPreKeySecret: spkPrivateKeyBytes,
            signedPreKeyPublic: spkPublicKeyBytes,
            signedPreKeySignature: Data(signatureBytes),
            oneTimePreKeys: oneTimePreKeys
        )

        return .success(keys)
    }

    // MARK: - Create Public Bundle

    /// Creates a public key bundle for sharing with peers
    /// Migrated from: CreatePublicBundle()
    public func createPublicBundle() -> Result<PublicKeyBundle, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("IdentityKeys has been disposed"))
        }

        let opkRecords = oneTimePreKeys.map { opk in
            OneTimePreKeyRecord(preKeyId: opk.preKeyId, publicKey: opk.getPublicKey())
        }

        let bundle = PublicKeyBundle(
            ed25519PublicKey: Data(ed25519PublicKey),
            identityX25519: Data(identityX25519PublicKey),
            signedPreKeyId: signedPreKeyId,
            signedPreKeyPublic: Data(signedPreKeyPublic),
            signedPreKeySignature: Data(signedPreKeySignature),
            oneTimePreKeys: opkRecords,
            ephemeralX25519: ephemeralPublicKey.map { Data($0) }
        )

        return .success(bundle)
    }

    // MARK: - Generate Ephemeral Key Pair

    /// Generates an ephemeral key pair for X3DH
    /// Migrated from: GenerateEphemeralKeyPair()
    public func generateEphemeralKeyPair() -> Result<Unit, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("IdentityKeys has been disposed"))
        }

        // Clean up old ephemeral keys
        if ephemeralSecretKey != nil {
            CryptographicHelpers.secureWipe(&ephemeralSecretKey!)
        }
        if ephemeralPublicKey != nil {
            CryptographicHelpers.secureWipe(&ephemeralPublicKey!)
        }

        // Generate new ephemeral key pair
        let x25519 = X25519KeyExchange()
        let (privateKey, publicKey) = x25519.generateKeyPair()
        ephemeralSecretKey = x25519.privateKeyToBytes(privateKey)
        ephemeralPublicKey = x25519.publicKeyToBytes(publicKey)

        return .success(.value)
    }

    // MARK: - X3DH Key Agreement (Initiator)

    /// Performs X3DH key agreement as the initiator
    /// Migrated from: X3dhDeriveSharedSecret()
    public func x3dhDeriveSharedSecret(
        remoteBundle: PublicKeyBundle,
        info: Data
    ) -> Result<Data, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("IdentityKeys has been disposed"))
        }

        guard let ephemeralSecretKey = ephemeralSecretKey else {
            return .failure(.generic("Ephemeral key not generated"))
        }

        // Validate remote bundle
        guard remoteBundle.identityX25519.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic("Invalid remote identity key size"))
        }
        guard remoteBundle.signedPreKeyPublic.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic("Invalid remote signed pre-key size"))
        }

        let x25519 = X25519KeyExchange()

        do {
            // DH1 = DH(IKa, SPKb)
            let dh1 = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: identityX25519SecretKey,
                publicKeyBytes: remoteBundle.signedPreKeyPublic
            )

            // DH2 = DH(EKa, IKb)
            let dh2 = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: ephemeralSecretKey,
                publicKeyBytes: remoteBundle.identityX25519
            )

            // DH3 = DH(EKa, SPKb)
            let dh3 = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: ephemeralSecretKey,
                publicKeyBytes: remoteBundle.signedPreKeyPublic
            )

            // DH4 = DH(EKa, OPKb) if one-time pre-key is available
            var dhCombined = Data()
            dhCombined.append(dh1)
            dhCombined.append(dh2)
            dhCombined.append(dh3)

            if let firstOpk = remoteBundle.oneTimePreKeys.first,
               firstOpk.publicKey.count == CryptographicConstants.x25519KeySize {
                let dh4 = try x25519.performKeyAgreementWithBytes(
                    privateKeyBytes: ephemeralSecretKey,
                    publicKeyBytes: firstOpk.publicKey
                )
                dhCombined.append(dh4)
            }

            // Derive shared secret using HKDF
            // Input Key Material = 0xFF || DH1 || DH2 || DH3 || [DH4]
            var ikm = Data([0xFF])
            ikm.append(dhCombined)

            let sharedSecret = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: ikm,
                salt: nil,
                info: info,
                outputByteCount: CryptographicConstants.x25519KeySize
            )

            return .success(sharedSecret)
        } catch {
            return .failure(.generic("X3DH key agreement failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - X3DH Key Agreement (Recipient)

    /// Calculates shared secret as the recipient
    /// Migrated from: CalculateSharedSecretAsRecipient()
    public func calculateSharedSecretAsRecipient(
        remoteIdentityPublicKey: Data,
        remoteEphemeralPublicKey: Data,
        usedLocalOpkId: UInt32?,
        info: Data
    ) -> Result<Data, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("IdentityKeys has been disposed"))
        }

        // Validate remote keys
        guard remoteIdentityPublicKey.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic("Invalid remote identity key size"))
        }
        guard remoteEphemeralPublicKey.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic("Invalid remote ephemeral key size"))
        }

        let x25519 = X25519KeyExchange()

        do {
            // DH1 = DH(SPKb, IKa)
            let dh1 = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: signedPreKeySecret,
                publicKeyBytes: remoteEphemeralPublicKey
            )

            // DH2 = DH(IKb, EKa)
            let dh2 = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: identityX25519SecretKey,
                publicKeyBytes: remoteEphemeralPublicKey
            )

            // DH3 = DH(SPKb, EKa)
            let dh3 = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: signedPreKeySecret,
                publicKeyBytes: remoteIdentityPublicKey
            )

            // Note: Order matches initiator for symmetric result
            var dhCombined = Data()
            dhCombined.append(dh3)  // Maps to initiator's DH1
            dhCombined.append(dh2)  // Maps to initiator's DH2
            dhCombined.append(dh1)  // Maps to initiator's DH3

            // DH4 = DH(OPKb, EKa) if one-time pre-key was used
            if let opkId = usedLocalOpkId {
                guard let opk = oneTimePreKeys.first(where: { $0.preKeyId == opkId }) else {
                    return .failure(.generic("Used one-time pre-key not found: \(opkId)"))
                }

                guard let opkPrivateKey = opk.getPrivateKey() else {
                    return .failure(.generic("One-time pre-key private key not available"))
                }

                let dh4 = try x25519.performKeyAgreementWithBytes(
                    privateKeyBytes: opkPrivateKey,
                    publicKeyBytes: remoteEphemeralPublicKey
                )
                dhCombined.append(dh4)
            }

            // Derive shared secret using HKDF
            var ikm = Data([0xFF])
            ikm.append(dhCombined)

            let sharedSecret = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: ikm,
                salt: nil,
                info: info,
                outputByteCount: CryptographicConstants.x25519KeySize
            )

            return .success(sharedSecret)
        } catch {
            return .failure(.generic("Recipient key agreement failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Verify Remote Signed Pre-Key

    /// Verifies a remote signed pre-key signature
    /// Migrated from: VerifyRemoteSpkSignature()
    public static func verifyRemoteSpkSignature(
        remoteIdentityEd25519: Data,
        remoteSpkPublic: Data,
        remoteSpkSignature: Data
    ) -> Result<Bool, ProtocolFailure> {

        guard remoteIdentityEd25519.count == 32 else {
            return .failure(.generic("Invalid Ed25519 public key size"))
        }
        guard remoteSpkPublic.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic("Invalid signed pre-key size"))
        }
        guard remoteSpkSignature.count == 64 else {
            return .failure(.generic("Invalid signature size"))
        }

        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: remoteIdentityEd25519)
            let isValid = publicKey.isValidSignature(remoteSpkSignature, for: remoteSpkPublic)
            return .success(isValid)
        } catch {
            return .failure(.generic("Signature verification failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - State Serialization

    /// Serializes identity keys to protobuf state
    /// Migrated from: ToProtoState()
    public func toProtoState() -> Result<IdentityKeysState, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("IdentityKeys has been disposed"))
        }

        let opkSecrets = oneTimePreKeys.compactMap { opk -> OneTimePreKeySecret? in
            guard let privateKey = opk.getPrivateKey() else { return nil }
            return OneTimePreKeySecret(
                preKeyId: opk.preKeyId,
                privateKey: privateKey,
                publicKey: opk.getPublicKey()
            )
        }

        let state = IdentityKeysState(
            ed25519SecretKey: Data(ed25519SecretKey),
            identityX25519SecretKey: Data(identityX25519SecretKey),
            signedPreKeySecret: Data(signedPreKeySecret),
            oneTimePreKeys: opkSecrets,
            ed25519PublicKey: Data(ed25519PublicKey),
            identityX25519PublicKey: Data(identityX25519PublicKey),
            signedPreKeyId: signedPreKeyId,
            signedPreKeyPublic: Data(signedPreKeyPublic),
            signedPreKeySignature: Data(signedPreKeySignature)
        )

        return .success(state)
    }

    /// Restores identity keys from protobuf state
    /// Migrated from: FromProtoState()
    public static func fromProtoState(_ state: IdentityKeysState) -> Result<IdentityKeys, ProtocolFailure> {
        // Recreate one-time pre-keys
        var oneTimePreKeys: [OneTimePreKey] = []
        for opkSecret in state.oneTimePreKeys {
            let opk = OneTimePreKey(
                preKeyId: opkSecret.preKeyId,
                privateKey: Data(opkSecret.privateKey),
                publicKey: Data(opkSecret.publicKey)
            )
            oneTimePreKeys.append(opk)
        }

        let keys = IdentityKeys(
            ed25519SecretKey: Data(state.ed25519SecretKey),
            ed25519PublicKey: Data(state.ed25519PublicKey),
            identityX25519SecretKey: Data(state.identityX25519SecretKey),
            identityX25519PublicKey: Data(state.identityX25519PublicKey),
            signedPreKeyId: state.signedPreKeyId,
            signedPreKeySecret: Data(state.signedPreKeySecret),
            signedPreKeyPublic: Data(state.signedPreKeyPublic),
            signedPreKeySignature: Data(state.signedPreKeySignature),
            oneTimePreKeys: oneTimePreKeys
        )

        return .success(keys)
    }

    // MARK: - Get Identity X25519 Public Key

    public func getIdentityX25519PublicKey() -> Data {
        return Data(identityX25519PublicKey)
    }

    // MARK: - Dispose

    public func dispose() {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else { return }
        isDisposed = true

        // Wipe all secret keys
        CryptographicHelpers.secureWipe(&ed25519SecretKey)
        CryptographicHelpers.secureWipe(&identityX25519SecretKey)
        CryptographicHelpers.secureWipe(&signedPreKeySecret)

        if ephemeralSecretKey != nil {
            CryptographicHelpers.secureWipe(&ephemeralSecretKey!)
        }
        if ephemeralPublicKey != nil {
            CryptographicHelpers.secureWipe(&ephemeralPublicKey!)
        }

        // Dispose all one-time pre-keys
        for opk in oneTimePreKeys {
            opk.dispose()
        }
        oneTimePreKeys.removeAll()
    }
}

// MARK: - Debug Description
extension IdentityKeys: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "IdentityKeys(signedPreKeyId: \(signedPreKeyId), oneTimePreKeys: \(oneTimePreKeys.count))"
    }
}
