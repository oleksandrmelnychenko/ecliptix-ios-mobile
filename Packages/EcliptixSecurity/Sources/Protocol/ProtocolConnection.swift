import Crypto
import EcliptixCore
import Foundation

public struct RatchetConfig: Sendable {
    public let cacheWindowSize: UInt32
    public let ratchetIntervalSeconds: TimeInterval
    public let dhRatchetEveryNMessages: UInt32
    public let ratchetOnNewDhKey: Bool

    public static let `default` = RatchetConfig(
        cacheWindowSize: 100,
        ratchetIntervalSeconds: 300,
        dhRatchetEveryNMessages: 100,
        ratchetOnNewDhKey: true
    )

    public init(
        cacheWindowSize: UInt32,
        ratchetIntervalSeconds: TimeInterval,
        dhRatchetEveryNMessages: UInt32 = 100,
        ratchetOnNewDhKey: Bool = true
    ) {
        self.cacheWindowSize = cacheWindowSize
        self.ratchetIntervalSeconds = ratchetIntervalSeconds
        self.dhRatchetEveryNMessages = dhRatchetEveryNMessages
        self.ratchetOnNewDhKey = ratchetOnNewDhKey
    }

    public func shouldRatchet(currentIndex: UInt32, lastRatchetTime: Date, receivedNewDhKey: Bool) -> Bool {
        if ratchetOnNewDhKey && receivedNewDhKey {
            return true
        }

        if currentIndex > 0 && currentIndex % dhRatchetEveryNMessages == 0 {
            return true
        }

        let timeSinceLastRatchet = Date().timeIntervalSince(lastRatchetTime)
        return timeSinceLastRatchet >= ratchetIntervalSeconds
    }
}

public final class ProtocolConnection: @unchecked Sendable {
    private let id: UInt32
    private let isInitiator: Bool
    private let createdAt: Date
    private let ratchetConfig: RatchetConfig
    private let sessionTimeout: TimeInterval = 3600

    private var sendingChain: ProtocolChainStep
    private var receivingChain: ProtocolChainStep?

    private var rootKey: Data

    private var sendingDhPrivateKey: Data
    private var sendingDhPublicKey: Data
    private var peerDhPublicKey: Data?

    private var persistentDhPrivateKey: Data?
    private var persistentDhPublicKey: Data?

    private var metadataEncryptionKey: Data?

    private var peerBundle: PublicKeyBundle?

    private var lastRatchetTime: Date
    private var isFirstReceivingRatchet = true
    private var receivedNewDhKey = false

    private var nonceCounter: Int64 = 1000

    private let replayProtection: ReplayProtection
    private let ratchetRecovery: RatchetRecovery

    private var isDisposed = false
    private let lock = NSRecursiveLock()
    private init(
        id: UInt32,
        isInitiator: Bool,
        sendingChain: ProtocolChainStep,
        receivingChain: ProtocolChainStep?,
        rootKey: Data,
        sendingDhPrivateKey: Data,
        sendingDhPublicKey: Data,
        persistentDhPrivateKey: Data?,
        persistentDhPublicKey: Data?,
        ratchetConfig: RatchetConfig
    ) {
        self.id = id
        self.isInitiator = isInitiator
        self.sendingChain = sendingChain
        self.receivingChain = receivingChain
        self.rootKey = rootKey
        self.sendingDhPrivateKey = sendingDhPrivateKey
        self.sendingDhPublicKey = sendingDhPublicKey
        self.persistentDhPrivateKey = persistentDhPrivateKey
        self.persistentDhPublicKey = persistentDhPublicKey
        self.ratchetConfig = ratchetConfig
        self.createdAt = Date()
        self.lastRatchetTime = Date()
        self.replayProtection = ReplayProtection()
        self.ratchetRecovery = RatchetRecovery()
    }

    deinit {
        dispose()
    }

    public static func create(
        connectionId: UInt32,
        isInitiator: Bool,
        initialRootKey: Data,
        initialChainKey: Data,
        ratchetConfig: RatchetConfig = .default
    ) -> Result<ProtocolConnection, ProtocolFailure> {

        guard initialRootKey.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic("Root key must be 32 bytes"))
        }

        let x25519 = X25519KeyExchange()
        let (dhPrivateKey, dhPublicKey) = x25519.generateKeyPair()
        let dhPrivateKeyBytes = x25519.privateKeyToBytes(dhPrivateKey)
        let dhPublicKeyBytes = x25519.publicKeyToBytes(dhPublicKey)

        let (persistentDhPrivateKey, persistentDhPublicKey) = x25519.generateKeyPair()
        let persistentDhPrivateKeyBytes = x25519.privateKeyToBytes(persistentDhPrivateKey)
        let persistentDhPublicKeyBytes = x25519.publicKeyToBytes(persistentDhPublicKey)

        let sendingChain: ProtocolChainStep
        do {
            sendingChain = try ProtocolChainStep.create(
                stepType: .sending,
                initialChainKey: initialChainKey,
                initialDhPrivateKey: dhPrivateKeyBytes,
                initialDhPublicKey: dhPublicKeyBytes,
                cacheWindowSize: ratchetConfig.cacheWindowSize
            )
        } catch {
            return .failure(.generic("Failed to create sending chain: \(error.localizedDescription)"))
        }

        let connection = ProtocolConnection(
            id: connectionId,
            isInitiator: isInitiator,
            sendingChain: sendingChain,
            receivingChain: nil,
            rootKey: Data(initialRootKey),
            sendingDhPrivateKey: dhPrivateKeyBytes,
            sendingDhPublicKey: dhPublicKeyBytes,
            persistentDhPrivateKey: persistentDhPrivateKeyBytes,
            persistentDhPublicKey: persistentDhPublicKeyBytes,
            ratchetConfig: ratchetConfig
        )

        _ = connection.deriveMetadataEncryptionKey()

        return .success(connection)
    }

    public func toProtoState() -> Result<RatchetState, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        let sendingStepState: ChainStepState
        do {
            sendingStepState = try sendingChain.toProtoState()
        } catch {
            return .failure(.generic("Failed to serialize sending chain: \(error.localizedDescription)"))
        }

        var receivingStepState: ChainStepState?
        if let receivingChain = receivingChain {
            do {
                receivingStepState = try receivingChain.toProtoState()
            } catch {
                return .failure(.generic("Failed to serialize receiving chain: \(error.localizedDescription)"))
            }
        }

        var state = RatchetState()
        state.isInitiator = isInitiator
        state.nonceCounter = UInt64(nonceCounter)
        if let peerBundle = peerBundle {
            state.peerBundle = peerBundle
        }
        state.peerDhPublicKey = peerDhPublicKey ?? Data()
        state.isFirstReceivingRatchet = isFirstReceivingRatchet
        state.rootKey = rootKey
        state.sendingStep = sendingStepState
        if let receivingStepState = receivingStepState {
            state.receivingStep = receivingStepState
        }

        return .success(state)
    }

    public static func fromProtoState(
        connectionId: UInt32,
        state: RatchetState,
        ratchetConfig: RatchetConfig = .default
    ) -> Result<ProtocolConnection, ProtocolFailure> {

        let sendingChain: ProtocolChainStep
        do {
            sendingChain = try ProtocolChainStep.fromProtoState(
                stepType: .sending,
                state: state.sendingStep
            )
        } catch {
            return .failure(.generic("Failed to restore sending chain: \(error.localizedDescription)"))
        }

        var receivingChain: ProtocolChainStep?
        if state.hasReceivingStep {
            do {
                receivingChain = try ProtocolChainStep.fromProtoState(
                    stepType: .receiving,
                    state: state.receivingStep
                )
            } catch {
                return .failure(.generic("Failed to restore receiving chain: \(error.localizedDescription)"))
            }
        }

        guard let sendingDhPrivateKey = sendingChain.getDhPrivateKey(),
              let sendingDhPublicKey = sendingChain.getDhPublicKey() else {
            return .failure(.generic("Failed to extract DH keys from sending chain"))
        }

        let connection = ProtocolConnection(
            id: connectionId,
            isInitiator: state.isInitiator,
            sendingChain: sendingChain,
            receivingChain: receivingChain,
            rootKey: Data(state.rootKey),
            sendingDhPrivateKey: sendingDhPrivateKey,
            sendingDhPublicKey: sendingDhPublicKey,
            persistentDhPrivateKey: nil,
            persistentDhPublicKey: nil,
            ratchetConfig: ratchetConfig
        )

        connection.nonceCounter = Int64(state.nonceCounter)
        if state.hasPeerBundle {
            connection.peerBundle = state.peerBundle
        }
        connection.peerDhPublicKey = state.peerDhPublicKey.isEmpty ? nil : Data(state.peerDhPublicKey)
        connection.isFirstReceivingRatchet = state.isFirstReceivingRatchet

        _ = connection.deriveMetadataEncryptionKey()

        return .success(connection)
    }

    public func finalizeChainAndDhKeys(
        initialRootKey: Data,
        initialPeerDhPublicKey: Data
    ) -> Result<Void, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        if rootKey.count > 0 && receivingChain != nil {
            return .failure(.generic("Session already finalized"))
        }

        guard initialRootKey.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic("Invalid root key size"))
        }

        guard initialPeerDhPublicKey.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic("Invalid peer DH public key size"))
        }

        guard let persistentDhPrivateKey = persistentDhPrivateKey else {
            return .failure(.generic("Persistent DH private key not available"))
        }

        let x25519 = X25519KeyExchange()
        do {
            let dhSecret = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: persistentDhPrivateKey,
                publicKeyBytes: initialPeerDhPublicKey
            )

            let dhRatchetInfo = Data("ecliptix-dh-ratchet".utf8)
            let derived = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: dhSecret,
                salt: initialRootKey,
                info: dhRatchetInfo,
                outputByteCount: 64
            )

            let newRootKey = derived.prefix(32)
            let derivedKeyMaterial = derived.suffix(32)

            let senderChainInfo = Data("ecliptix-initial-sender-chain".utf8)
            let receiverChainInfo = Data("ecliptix-initial-receiver-chain".utf8)

            let senderChainKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: derivedKeyMaterial,
                salt: nil,
                info: senderChainInfo,
                outputByteCount: CryptographicConstants.x25519KeySize
            )

            let receiverChainKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: derivedKeyMaterial,
                salt: nil,
                info: receiverChainInfo,
                outputByteCount: CryptographicConstants.x25519KeySize
            )

            let finalSenderKey = isInitiator ? senderChainKey : receiverChainKey
            let finalReceiverKey = isInitiator ? receiverChainKey : senderChainKey

            do {
                try sendingChain.updateKeysAfterDhRatchet(newChainKey: finalSenderKey)
            } catch {
                return .failure(.generic("Failed to update sending chain: \(error.localizedDescription)"))
            }

            let newReceivingChain: ProtocolChainStep
            do {
                newReceivingChain = try ProtocolChainStep.create(
                    stepType: .receiving,
                    initialChainKey: finalReceiverKey,
                    initialDhPrivateKey: persistentDhPrivateKey,
                    initialDhPublicKey: persistentDhPublicKey!,
                    cacheWindowSize: ratchetConfig.cacheWindowSize
                )
            } catch {
                return .failure(.generic("Failed to create receiving chain: \(error.localizedDescription)"))
            }

            CryptographicHelpers.secureWipe(&rootKey)
            rootKey = Data(newRootKey)
            receivingChain = newReceivingChain
            peerDhPublicKey = Data(initialPeerDhPublicKey)

            _ = deriveMetadataEncryptionKey()

            return .success(())
        } catch {
            return .failure(.generic("DH ratchet failed: \(error.localizedDescription)"))
        }
    }

    public func prepareNextSendMessage() -> Result<(ratchetKey: RatchetChainKey, includeDhKey: Bool, dhPublicKey: Data?), ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        if Date().timeIntervalSince(createdAt) > sessionTimeout {
            return .failure(.generic("Session has expired"))
        }

        let currentIndex: UInt32
        do {
            currentIndex = try sendingChain.getCurrentIndex()
        } catch {
            return .failure(.generic("Failed to get current sending index: \(error.localizedDescription)"))
        }

        let shouldRatchet = ratchetConfig.shouldRatchet(
            currentIndex: currentIndex + 1,
            lastRatchetTime: lastRatchetTime,
            receivedNewDhKey: receivedNewDhKey
        )

        if shouldRatchet {
            _ = performDhRatchet(isSender: true)
        }

        let nextIndex = currentIndex + 1
        let ratchetKey: RatchetChainKey
        do {
            ratchetKey = try sendingChain.getOrDeriveKeyFor(targetIndex: nextIndex)
        } catch {
            return .failure(.generic("Failed to derive sending key: \(error.localizedDescription)"))
        }

        do {
            try sendingChain.setCurrentIndex(nextIndex)
        } catch {
            return .failure(.generic("Failed to update sending index: \(error.localizedDescription)"))
        }

        let dhPublicKey = shouldRatchet ? sendingDhPublicKey : nil
        return .success((ratchetKey, shouldRatchet, dhPublicKey))
    }

    public func processReceivedMessage(receivedIndex: UInt32) -> Result<RatchetChainKey, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        if Date().timeIntervalSince(createdAt) > sessionTimeout {
            return .failure(.generic("Session has expired"))
        }

        guard let receivingChain = receivingChain else {
            return .failure(.generic("Receiving chain not initialized"))
        }

        if let recoveredKey = ratchetRecovery.tryRecoverMessageKey(messageIndex: receivedIndex) {
            return .success(recoveredKey)
        }

        let currentIndex: UInt32
        do {
            currentIndex = try receivingChain.getCurrentIndex()
        } catch {
            return .failure(.generic("Failed to get current receiving index: \(error.localizedDescription)"))
        }

        if receivedIndex > currentIndex + 1 {
            let chainKey: Data
            do {
                chainKey = try receivingChain.getCurrentChainKey()
            } catch {
                return .failure(.generic("Failed to get current chain key: \(error.localizedDescription)"))
            }

            do {
                try ratchetRecovery.storeSkippedMessageKeys(
                    currentChainKey: chainKey,
                    fromIndex: currentIndex + 1,
                    toIndex: receivedIndex
                )
            } catch {
                Log.warning("[ProtocolConnection] Failed to store skipped message keys: \(error.localizedDescription)")
            }
        }

        let ratchetKey: RatchetChainKey
        do {
            ratchetKey = try receivingChain.getOrDeriveKeyFor(targetIndex: receivedIndex)
        } catch {
            return .failure(.generic("Failed to derive receiving key: \(error.localizedDescription)"))
        }

        do {
            try receivingChain.setCurrentIndex(receivedIndex)
        } catch {
            return .failure(.generic("Failed to update receiving index: \(error.localizedDescription)"))
        }

        if receivedIndex > 1000 {
            ratchetRecovery.cleanupOldKeys(beforeIndex: receivedIndex - 1000)
        }

        return .success(ratchetKey)
    }

    public func performReceivingRatchet(receivedDhPublicKey: Data) -> Result<Void, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        guard receivedDhPublicKey.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic("Invalid DH public key size"))
        }

        receivedNewDhKey = true
        peerDhPublicKey = Data(receivedDhPublicKey)

        guard let receivingChain = receivingChain else {
            return .failure(.generic("Receiving chain not initialized"))
        }

        let currentIndex: UInt32
        do {
            currentIndex = try receivingChain.getCurrentIndex()
        } catch {
            return .failure(.generic("Failed to get receiving index: \(error.localizedDescription)"))
        }

        let shouldRatchet = isFirstReceivingRatchet ||
            ratchetConfig.shouldRatchet(currentIndex: currentIndex + 1, lastRatchetTime: lastRatchetTime, receivedNewDhKey: receivedNewDhKey)

        if shouldRatchet {
            isFirstReceivingRatchet = false
            return performDhRatchet(isSender: false, receivedDhPublicKey: receivedDhPublicKey)
        }

        return .success(())
    }

    private func performDhRatchet(isSender: Bool, receivedDhPublicKey: Data? = nil) -> Result<Void, ProtocolFailure> {
        guard let peerKey = isSender ? peerDhPublicKey : receivedDhPublicKey else {
            return .failure(.generic("Peer DH public key not available"))
        }

        do {
            let x25519 = X25519KeyExchange()

            let dhSecret = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: sendingDhPrivateKey,
                publicKeyBytes: peerKey
            )

            let dhRatchetInfo = Data("ecliptix-dh-ratchet".utf8)
            let derived = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: dhSecret,
                salt: rootKey,
                info: dhRatchetInfo,
                outputByteCount: 64
            )

            let newRootKey = derived.prefix(32)
            let newChainKey = derived.suffix(32)

            CryptographicHelpers.secureWipe(&rootKey)
            rootKey = Data(newRootKey)

            if isSender {

                let (newPrivateKey, newPublicKey) = x25519.generateKeyPair()
                let newPrivateKeyBytes = x25519.privateKeyToBytes(newPrivateKey)
                let newPublicKeyBytes = x25519.publicKeyToBytes(newPublicKey)

                try sendingChain.updateKeysAfterDhRatchet(
                    newChainKey: Data(newChainKey),
                    newDhPrivateKey: newPrivateKeyBytes,
                    newDhPublicKey: newPublicKeyBytes
                )

                CryptographicHelpers.secureWipe(&sendingDhPrivateKey)
                sendingDhPrivateKey = newPrivateKeyBytes
                sendingDhPublicKey = newPublicKeyBytes
            } else {
                try receivingChain?.updateKeysAfterDhRatchet(newChainKey: Data(newChainKey))
                peerDhPublicKey = Data(peerKey)
            }

            lastRatchetTime = Date()
            receivedNewDhKey = false
            replayProtection.onRatchetRotation()

            _ = deriveMetadataEncryptionKey()

            return .success(())
        } catch {
            return .failure(.generic("DH ratchet failed: \(error.localizedDescription)"))
        }
    }

    public func getMetadataEncryptionKey() -> Result<Data, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        if let key = metadataEncryptionKey {
            return .success(Data(key))
        }

        return deriveMetadataEncryptionKey()
    }

    public func checkReplayProtection(nonce: Data, messageIndex: UInt32) -> Result<Void, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        return replayProtection.checkAndRecordMessage(
            nonce: nonce,
            messageIndex: UInt64(messageIndex),
            chainIndex: 0
        )
    }

    public func getCurrentSenderDhPublicKey() -> Result<Data?, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        return .success(Data(sendingDhPublicKey))
    }
    public func getSendingChainIndex() throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            throw ProtocolFailure.generic("Connection has been disposed")
        }

        return try sendingChain.getCurrentIndex()
    }
    public func getReceivingChainIndex() throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            throw ProtocolFailure.generic("Connection has been disposed")
        }

        guard let chain = receivingChain else {
            throw ProtocolFailure.generic("No receiving chain")
        }

        return try chain.getCurrentIndex()
    }

    public func generateNonce() -> Data {
        lock.lock()
        defer { lock.unlock() }

        nonceCounter += 1
        var nonce = Data(count: CryptographicConstants.aesGcmNonceSize)

        var counter = nonceCounter.littleEndian
        withUnsafeBytes(of: &counter) { buffer in
            nonce.replaceSubrange(0..<8, with: buffer)
        }

        let randomBytes = CryptographicHelpers.generateRandomBytes(count: 4)
        nonce.replaceSubrange(8..<12, with: randomBytes)

        return nonce
    }
    public func setPeerBundle(_ bundle: PublicKeyBundle) -> Result<Void, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        peerBundle = bundle
        return .success(())
    }
    public func getPeerBundle() -> Result<PublicKeyBundle, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        guard let bundle = peerBundle else {
            return .failure(.generic("Peer bundle not set"))
        }

        return .success(bundle)
    }

    private func deriveMetadataEncryptionKey() -> Result<Data, ProtocolFailure> {
        do {
            let key = try HKDFKeyDerivation.deriveMetadataEncryptionKey(from: rootKey)
            metadataEncryptionKey = key
            return .success(key)
        } catch {
            return .failure(.generic("Failed to derive metadata encryption key: \(error.localizedDescription)"))
        }
    }
    public func dispose() {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else { return }
        isDisposed = true

        CryptographicHelpers.secureWipe(&rootKey)
        CryptographicHelpers.secureWipe(&sendingDhPrivateKey)
        if metadataEncryptionKey != nil {
            CryptographicHelpers.secureWipe(&metadataEncryptionKey!)
        }
        if peerDhPublicKey != nil {
            CryptographicHelpers.secureWipe(&peerDhPublicKey!)
        }
        if persistentDhPrivateKey != nil {
            CryptographicHelpers.secureWipe(&persistentDhPrivateKey!)
        }
    }
}
extension ProtocolConnection: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "ProtocolConnection(id: \(id), isInitiator: \(isInitiator), hasReceivingChain: \(receivingChain != nil))"
    }
}
