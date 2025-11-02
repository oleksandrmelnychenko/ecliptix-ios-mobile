import Crypto
import EcliptixCore
import Foundation

public enum ChainStepType {
    case sending
    case receiving
}

public final class ProtocolChainStep: KeyProvider {

    public static let defaultCacheWindowSize: UInt32 = 100
    private static let initialIndex: UInt32 = 0
    private static let indexIncrement: UInt32 = 1

    private let stepType: ChainStepType
    private let cacheWindow: UInt32

    private var chainKey: Data

    private var messageKeys: [UInt32: Data] = [:]

    private var currentIndex: UInt32

    private var dhPrivateKey: Data?
    private var dhPublicKey: Data?
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

        for key in messageKeys.keys {
            if var data = messageKeys[key] {
                CryptographicHelpers.secureWipe(&data)
            }
        }

        CryptographicHelpers.secureWipe(&chainKey)

        if dhPrivateKey != nil {
            CryptographicHelpers.secureWipe(&dhPrivateKey!)
        }
        if dhPublicKey != nil {
            CryptographicHelpers.secureWipe(&dhPublicKey!)
        }
    }

    public static func create(
        stepType: ChainStepType,
        initialChainKey: Data,
        initialDhPrivateKey: Data? = nil,
        initialDhPublicKey: Data? = nil,
        cacheWindowSize: UInt32 = defaultCacheWindowSize
    ) throws -> ProtocolChainStep {
        guard initialChainKey.count == CryptographicConstants.x25519KeySize else {
            throw ProtocolFailure.generic(
                "Initial chain key must be \(CryptographicConstants.x25519KeySize) bytes, got \(initialChainKey.count)"
            )
        }

        if let dhPrivate = initialDhPrivateKey, let dhPublic = initialDhPublicKey {
            guard dhPrivate.count == CryptographicConstants.x25519PrivateKeySize else {
                throw ProtocolFailure.generic(
                    "DH private key must be \(CryptographicConstants.x25519PrivateKeySize) bytes"
                )
            }
            guard dhPublic.count == CryptographicConstants.x25519KeySize else {
                throw ProtocolFailure.generic(
                    "DH public key must be \(CryptographicConstants.x25519KeySize) bytes"
                )
            }
        } else if initialDhPrivateKey != nil || initialDhPublicKey != nil {
            throw ProtocolFailure.generic("Both DH private and public keys must be provided, or neither")
        }

        let actualCacheWindow = cacheWindowSize > 0 ? cacheWindowSize : defaultCacheWindowSize
        let step = ProtocolChainStep(
            stepType: stepType,
            chainKey: Data(initialChainKey),
            dhPrivateKey: initialDhPrivateKey.map { Data($0) },
            dhPublicKey: initialDhPublicKey.map { Data($0) },
            cacheWindowSize: actualCacheWindow
        )

        return step
    }
    public func getCurrentIndex() throws -> UInt32 {
        return currentIndex
    }
    func setCurrentIndex(_ value: UInt32) throws {
        currentIndex = value
    }
    func getCurrentChainKey() throws -> Data {
        return Data(chainKey)
    }
    public func getDhPublicKey() -> Data? {
        return dhPublicKey.map { Data($0) }
    }

    public func getDhPrivateKey() -> Data? {
        return dhPrivateKey.map { Data($0) }
    }
    func executeWithKey<T>(
        keyIndex: UInt32,
        operation: (Data) throws -> T
    ) throws -> T {
        guard let keyData = messageKeys[keyIndex] else {
            throw ProtocolFailure.generic("Key with index \(keyIndex) not found")
        }

        return try operation(keyData)
    }

    public func getOrDeriveKeyFor(targetIndex: UInt32) throws -> RatchetChainKey {

        if messageKeys[targetIndex] != nil {
            return RatchetChainKey(index: targetIndex, keyProvider: self)
        }

        guard targetIndex > currentIndex else {
            throw ProtocolFailure.generic(
                "Requested index \(targetIndex) must be greater than current index \(currentIndex) for \(stepType)"
            )
        }

        var tempChainKey = Data(chainKey)
        defer {
            CryptographicHelpers.secureWipe(&tempChainKey)
        }

        for index in (currentIndex + Self.indexIncrement)...targetIndex {
            do {

                let (messageKey, nextChainKey) = try HKDFKeyDerivation.deriveChainAndMessageKey(
                    from: tempChainKey
                )

                messageKeys[index] = messageKey

                tempChainKey = nextChainKey

                chainKey = Data(nextChainKey)
            } catch {
                throw ProtocolFailure.generic(
                    "HKDF derivation failed during iteration at index \(index): \(error.localizedDescription)"
                )
            }
        }

        currentIndex = targetIndex

        pruneOldKeys()

        guard messageKeys[targetIndex] != nil else {
            throw ProtocolFailure.generic("Derived key missing after loop for index \(targetIndex)")
        }

        return RatchetChainKey(index: targetIndex, keyProvider: self)
    }

    public func skipKeysUntil(targetIndex: UInt32) throws {
        guard targetIndex > currentIndex else {
            return
        }

        for index in (currentIndex + Self.indexIncrement)...targetIndex {
            _ = try getOrDeriveKeyFor(targetIndex: index)
        }
    }

    public func pruneOldKeys() {
        let windowStart = currentIndex > cacheWindow ? currentIndex - cacheWindow : 0

        let keysToRemove = messageKeys.keys.filter { $0 < windowStart }
        for key in keysToRemove {
            if var data = messageKeys[key] {
                CryptographicHelpers.secureWipe(&data)
            }
            messageKeys.removeValue(forKey: key)
        }
    }

    public func updateKeysAfterDhRatchet(
        newChainKey: Data,
        newDhPrivateKey: Data? = nil,
        newDhPublicKey: Data? = nil
    ) throws {

        for key in messageKeys.keys {
            if var data = messageKeys[key] {
                CryptographicHelpers.secureWipe(&data)
            }
        }
        messageKeys.removeAll()

        CryptographicHelpers.secureWipe(&chainKey)
        chainKey = Data(newChainKey)

        currentIndex = Self.initialIndex

        if let newPrivKey = newDhPrivateKey, let newPubKey = newDhPublicKey {
            if dhPrivateKey != nil {
                CryptographicHelpers.secureWipe(&dhPrivateKey!)
            }
            if dhPublicKey != nil {
                CryptographicHelpers.secureWipe(&dhPublicKey!)
            }
            dhPrivateKey = Data(newPrivKey)
            dhPublicKey = Data(newPubKey)
        }
    }

    public func toProtoState() throws -> ChainStepState {

        let cachedKeys = messageKeys.map { index, keyMaterial in
            var key = CachedMessageKey()
            key.index = index
            key.keyMaterial = keyMaterial
            return key
        }

        var state = ChainStepState()
        state.currentIndex = currentIndex
        state.chainKey = chainKey
        state.dhPrivateKey = dhPrivateKey ?? Data()
        state.dhPublicKey = dhPublicKey ?? Data()
        state.cachedMessageKeys = cachedKeys

        return state
    }

    public static func fromProtoState(
        stepType: ChainStepType,
        state: ChainStepState
    ) throws -> ProtocolChainStep {
        guard state.chainKey.count == CryptographicConstants.x25519KeySize else {
            throw ProtocolFailure.generic("Invalid chain key size in proto state")
        }

        let dhPrivateKey = state.dhPrivateKey.isEmpty ? nil : Data(state.dhPrivateKey)
        let dhPublicKey = state.dhPublicKey.isEmpty ? nil : Data(state.dhPublicKey)

        let step = ProtocolChainStep(
            stepType: stepType,
            chainKey: Data(state.chainKey),
            dhPrivateKey: dhPrivateKey,
            dhPublicKey: dhPublicKey,
            cacheWindowSize: defaultCacheWindowSize
        )

        step.currentIndex = state.currentIndex

        for cachedKey in state.cachedMessageKeys {
            step.messageKeys[cachedKey.index] = Data(cachedKey.keyMaterial)
        }

        return step
    }

}
extension ProtocolChainStep: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "ProtocolChainStep(type: \(stepType), currentIndex: \(currentIndex), cachedKeys: \(messageKeys.count))"
    }
}
