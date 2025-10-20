import Foundation
import Crypto
import EcliptixCore

// MARK: - Chain Step Type
/// Type of chain step (sending or receiving)
public enum ChainStepType {
    case sending
    case receiving
}

// MARK: - Protocol Chain Step
/// Manages ratchet chain key derivation and message key generation
/// Migrated from: Ecliptix.Protocol.System.Core.EcliptixProtocolChainStep.cs
public final class ProtocolChainStep: KeyProvider {

    private static let defaultCacheWindowSize: UInt32 = 100
    private static let initialIndex: UInt32 = 0
    private static let indexIncrement: UInt32 = 1

    private let stepType: ChainStepType
    private let cacheWindow: UInt32

    // Current chain key (32 bytes)
    private var chainKey: Data

    // Message keys cache: [index: key]
    private var messageKeys: [UInt32: Data] = [:]

    // Current ratchet index
    private var currentIndex: UInt32

    // DH keys for ratcheting (optional)
    private var dhPrivateKey: Data?
    private var dhPublicKey: Data?

    // Disposed flag
    private var isDisposed = false

    // MARK: - Initialization
    private init(
        stepType: ChainStepType,
        chainKey: Data,
        dhPrivateKey: Data?,
        dhPublicKey: Data?,
        cacheWindowSize: UInt32
    ) {
        self.stepType = stepType
        self.chainKey = chainKey
        self.dhPrivateKey = dhPrivateKey
        self.dhPublicKey = dhPublicKey
        self.cacheWindow = cacheWindowSize
        self.currentIndex = Self.initialIndex
    }

    deinit {
        dispose()
    }

    // MARK: - Create
    /// Creates a new protocol chain step
    /// Migrated from: EcliptixProtocolChainStep.Create()
    public static func create(
        stepType: ChainStepType,
        initialChainKey: Data,
        initialDhPrivateKey: Data? = nil,
        initialDhPublicKey: Data? = nil,
        cacheWindowSize: UInt32 = defaultCacheWindowSize
    ) -> Result<ProtocolChainStep, ProtocolFailure> {
        // Validate initial chain key
        guard initialChainKey.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic(
                "Initial chain key must be \(CryptographicConstants.x25519KeySize) bytes, got \(initialChainKey.count)"
            ))
        }

        // Validate DH keys
        if let dhPrivate = initialDhPrivateKey, let dhPublic = initialDhPublicKey {
            guard dhPrivate.count == CryptographicConstants.x25519PrivateKeySize else {
                return .failure(.generic(
                    "DH private key must be \(CryptographicConstants.x25519PrivateKeySize) bytes"
                ))
            }
            guard dhPublic.count == CryptographicConstants.x25519KeySize else {
                return .failure(.generic(
                    "DH public key must be \(CryptographicConstants.x25519KeySize) bytes"
                ))
            }
        } else if initialDhPrivateKey != nil || initialDhPublicKey != nil {
            return .failure(.generic("Both DH private and public keys must be provided, or neither"))
        }

        let actualCacheWindow = cacheWindowSize > 0 ? cacheWindowSize : defaultCacheWindowSize
        let step = ProtocolChainStep(
            stepType: stepType,
            chainKey: Data(initialChainKey),
            dhPrivateKey: initialDhPrivateKey.map { Data($0) },
            dhPublicKey: initialDhPublicKey.map { Data($0) },
            cacheWindowSize: actualCacheWindow
        )

        return .success(step)
    }

    // MARK: - Get Current Index
    public func getCurrentIndex() -> Result<UInt32, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("ProtocolChainStep has been disposed"))
        }
        return .success(currentIndex)
    }

    // MARK: - Set Current Index
    func setCurrentIndex(_ value: UInt32) -> Result<Unit, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("ProtocolChainStep has been disposed"))
        }
        currentIndex = value
        return .success(.value)
    }

    // MARK: - Get Current Chain Key
    func getCurrentChainKey() -> Result<Data, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("ProtocolChainStep has been disposed"))
        }
        return .success(Data(chainKey))
    }

    // MARK: - Get DH Public Key
    public func getDhPublicKey() -> Data? {
        return dhPublicKey.map { Data($0) }
    }

    // MARK: - Execute With Key (KeyProvider conformance)
    func executeWithKey<T>(
        keyIndex: UInt32,
        operation: (Data) -> Result<T, ProtocolFailure>
    ) -> Result<T, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("ProtocolChainStep has been disposed"))
        }

        guard let keyData = messageKeys[keyIndex] else {
            return .failure(.generic("Key with index \(keyIndex) not found"))
        }

        return operation(keyData)
    }

    // MARK: - Get Or Derive Key For Index
    /// Gets or derives a ratchet chain key for the target index
    /// Migrated from: GetOrDeriveKeyFor(uint targetIndex)
    public func getOrDeriveKeyFor(targetIndex: UInt32) -> Result<RatchetChainKey, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("ProtocolChainStep has been disposed"))
        }

        // If key already exists in cache, return it
        if messageKeys[targetIndex] != nil {
            return .success(RatchetChainKey(index: targetIndex, keyProvider: self))
        }

        // Validate target index is in the future
        guard targetIndex > currentIndex else {
            return .failure(.generic(
                "Requested index \(targetIndex) must be greater than current index \(currentIndex) for \(stepType)"
            ))
        }

        // Derive keys from current to target
        var tempChainKey = Data(chainKey)
        defer {
            CryptographicHelpers.secureWipe(&tempChainKey)
        }

        // Step through indices from current+1 to target
        for index in (currentIndex + Self.indexIncrement)...targetIndex {
            do {
                // Derive message key and next chain key using HKDF
                let (messageKey, nextChainKey) = try HKDFKeyDerivation.deriveChainAndMessageKey(
                    from: tempChainKey
                )

                // Store message key in cache
                messageKeys[index] = messageKey

                // Update chain key for next iteration
                tempChainKey = nextChainKey

                // Update the main chain key
                chainKey = Data(nextChainKey)
            } catch {
                return .failure(.generic(
                    "HKDF derivation failed during iteration at index \(index): \(error.localizedDescription)"
                ))
            }
        }

        // Update current index
        currentIndex = targetIndex

        // Prune old keys outside cache window
        pruneOldKeys()

        // Verify key was derived
        guard messageKeys[targetIndex] != nil else {
            return .failure(.generic("Derived key missing after loop for index \(targetIndex)"))
        }

        return .success(RatchetChainKey(index: targetIndex, keyProvider: self))
    }

    // MARK: - Skip Keys Until
    /// Skips keys until the target index, generating and caching them
    /// Migrated from: SkipKeysUntil(uint targetIndex)
    public func skipKeysUntil(targetIndex: UInt32) -> Result<Unit, ProtocolFailure> {
        guard targetIndex > currentIndex else {
            return .success(.value)
        }

        for index in (currentIndex + Self.indexIncrement)...targetIndex {
            let keyResult = getOrDeriveKeyFor(targetIndex: index)
            if case .failure(let error) = keyResult {
                return .failure(error)
            }
        }

        return .success(.value)
    }

    // MARK: - Prune Old Keys
    /// Removes keys outside the cache window to limit memory usage
    /// Migrated from: PruneOldKeys()
    private func pruneOldKeys() {
        let windowStart = currentIndex > cacheWindow ? currentIndex - cacheWindow : 0

        let keysToRemove = messageKeys.keys.filter { $0 < windowStart }
        for key in keysToRemove {
            if var data = messageKeys[key] {
                CryptographicHelpers.secureWipe(&data)
            }
            messageKeys.removeValue(forKey: key)
        }
    }

    // MARK: - Dispose
    /// Securely disposes of all key material
    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true

        // Wipe all message keys
        for key in messageKeys.keys {
            if var data = messageKeys[key] {
                CryptographicHelpers.secureWipe(&data)
            }
        }
        messageKeys.removeAll()

        // Wipe chain key
        CryptographicHelpers.secureWipe(&chainKey)

        // Wipe DH keys
        if dhPrivateKey != nil {
            CryptographicHelpers.secureWipe(&dhPrivateKey!)
        }
        if dhPublicKey != nil {
            CryptographicHelpers.secureWipe(&dhPublicKey!)
        }
    }
}

// MARK: - Debug Description
extension ProtocolChainStep: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "ProtocolChainStep(type: \(stepType), currentIndex: \(currentIndex), cachedKeys: \(messageKeys.count))"
    }
}
