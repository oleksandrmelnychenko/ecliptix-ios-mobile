import Foundation
import Crypto
import EcliptixCore

// MARK: - Ratchet Config
/// Configuration for ratchet behavior
public struct RatchetConfig {
    public let cacheWindowSize: UInt32
    public let ratchetIntervalSeconds: TimeInterval
    public let dhRatchetEveryNMessages: UInt32
    public let ratchetOnNewDhKey: Bool

    public static let `default` = RatchetConfig(
        cacheWindowSize: 100,
        ratchetIntervalSeconds: 300, // 5 minutes
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

// MARK: - Protocol Connection
/// Manages a secure protocol connection with Double Ratchet algorithm
/// Complete migration from: Ecliptix.Protocol.System.Core.EcliptixProtocolConnection.cs
public final class ProtocolConnection {

    // MARK: - Properties
    private let id: UInt32
    private let isInitiator: Bool
    private let createdAt: Date
    private let ratchetConfig: RatchetConfig
    private let sessionTimeout: TimeInterval = 3600 // 1 hour

    // Chains
    private var sendingChain: ProtocolChainStep
    private var receivingChain: ProtocolChainStep?

    // Root key for DH ratcheting
    private var rootKey: Data

    // DH keys
    private var sendingDhPrivateKey: Data
    private var sendingDhPublicKey: Data
    private var peerDhPublicKey: Data?

    // Persistent DH keys (for initial handshake)
    private var persistentDhPrivateKey: Data?
    private var persistentDhPublicKey: Data?

    // Metadata encryption key (derived from root key)
    private var metadataEncryptionKey: Data?

    // Peer information
    private var peerBundle: PublicKeyBundle?

    // State tracking
    private var lastRatchetTime: Date
    private var isFirstReceivingRatchet = true
    private var receivedNewDhKey = false

    // Nonce counter for sending
    private var nonceCounter: Int64 = 1000 // Start at 1000

    // Replay protection and recovery
    private let replayProtection: ReplayProtection
    private let ratchetRecovery: RatchetRecovery

    private var isDisposed = false
    private let lock = NSRecursiveLock()

    // MARK: - Initialization
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

    // MARK: - Create Connection
    /// Creates a new protocol connection
    /// Migrated from: EcliptixProtocolConnection.Create()
    public static func create(
        connectionId: UInt32,
        isInitiator: Bool,
        initialRootKey: Data,
        initialChainKey: Data,
        ratchetConfig: RatchetConfig = .default
    ) -> Result<ProtocolConnection, ProtocolFailure> {

        // Validate root key
        guard initialRootKey.count == CryptographicConstants.x25519KeySize else {
            return .failure(.generic("Root key must be 32 bytes"))
        }

        // Generate sending DH keys
        let x25519 = X25519KeyExchange()
        let (dhPrivateKey, dhPublicKey) = x25519.generateKeyPair()
        let dhPrivateKeyBytes = x25519.privateKeyToBytes(dhPrivateKey)
        let dhPublicKeyBytes = x25519.publicKeyToBytes(dhPublicKey)

        // Generate persistent DH keys
        let (persistentDhPrivateKey, persistentDhPublicKey) = x25519.generateKeyPair()
        let persistentDhPrivateKeyBytes = x25519.privateKeyToBytes(persistentDhPrivateKey)
        let persistentDhPublicKeyBytes = x25519.publicKeyToBytes(persistentDhPublicKey)

        // Create sending chain with DH keys
        let sendingChainResult = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey,
            initialDhPrivateKey: dhPrivateKeyBytes,
            initialDhPublicKey: dhPublicKeyBytes,
            cacheWindowSize: ratchetConfig.cacheWindowSize
        )

        guard case .success(let sendingChain) = sendingChainResult else {
            if case .failure(let error) = sendingChainResult {
                return .failure(error)
            }
            return .failure(.generic("Failed to create sending chain"))
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

        // Derive metadata encryption key
        _ = connection.deriveMetadataEncryptionKey()

        return .success(connection)
    }

    // MARK: - State Serialization
    /// Serializes connection state to protobuf format
    /// Migrated from: ToProtoState()
    public func toProtoState() -> Result<RatchetState, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        // Serialize sending chain
        guard case .success(let sendingStepState) = sendingChain.toProtoState() else {
            return .failure(.generic("Failed to serialize sending chain"))
        }

        // Serialize receiving chain if it exists
        var receivingStepState: ChainStepState?
        if let receivingChain = receivingChain {
            guard case .success(let state) = receivingChain.toProtoState() else {
                return .failure(.generic("Failed to serialize receiving chain"))
            }
            receivingStepState = state
        }

        let state = RatchetState(
            isInitiator: isInitiator,
            createdAt: createdAt,
            nonceCounter: UInt64(nonceCounter),
            peerBundle: peerBundle,
            peerDhPublicKey: peerDhPublicKey ?? Data(),
            isFirstReceivingRatchet: isFirstReceivingRatchet,
            rootKey: rootKey,
            sendingStep: sendingStepState,
            receivingStep: receivingStepState
        )

        return .success(state)
    }

    /// Restores connection from protobuf state
    /// Migrated from: FromProtoState()
    public static func fromProtoState(
        connectionId: UInt32,
        state: RatchetState,
        ratchetConfig: RatchetConfig = .default
    ) -> Result<ProtocolConnection, ProtocolFailure> {

        // Restore sending chain
        guard case .success(let sendingChain) = ProtocolChainStep.fromProtoState(
            stepType: .sending,
            state: state.sendingStep
        ) else {
            return .failure(.generic("Failed to restore sending chain"))
        }

        // Restore receiving chain if it exists
        var receivingChain: ProtocolChainStep?
        if let receivingStepState = state.receivingStep {
            guard case .success(let chain) = ProtocolChainStep.fromProtoState(
                stepType: .receiving,
                state: receivingStepState
            ) else {
                return .failure(.generic("Failed to restore receiving chain"))
            }
            receivingChain = chain
        }

        // Extract DH keys from sending chain
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
        connection.peerBundle = state.peerBundle
        connection.peerDhPublicKey = state.peerDhPublicKey.isEmpty ? nil : Data(state.peerDhPublicKey)
        connection.isFirstReceivingRatchet = state.isFirstReceivingRatchet

        // Derive metadata encryption key
        _ = connection.deriveMetadataEncryptionKey()

        return .success(connection)
    }

    // MARK: - Finalize Chain and DH Keys
    /// Finalizes the connection with initial root key and peer DH key
    /// Migrated from: FinalizeChainAndDhKeys()
    public func finalizeChainAndDhKeys(
        initialRootKey: Data,
        initialPeerDhPublicKey: Data
    ) -> Result<Unit, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        // Fail if session is already finalized (both rootKey and receivingChain are set)
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

        // Perform DH key agreement
        let x25519 = X25519KeyExchange()
        do {
            let dhSecret = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: persistentDhPrivateKey,
                publicKeyBytes: initialPeerDhPublicKey
            )

            // Derive new root key using HKDF
            let dhRatchetInfo = Data("ecliptix-dh-ratchet".utf8)
            let derived = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: dhSecret,
                salt: initialRootKey,
                info: dhRatchetInfo,
                outputByteCount: 64 // 32 for root key + 32 for chains
            )

            let newRootKey = derived.prefix(32)
            let derivedKeyMaterial = derived.suffix(32)

            // Derive sender and receiver chain keys
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

            // Assign keys based on initiator status
            let finalSenderKey = isInitiator ? senderChainKey : receiverChainKey
            let finalReceiverKey = isInitiator ? receiverChainKey : senderChainKey

            // Update sending chain with new key
            guard case .success = sendingChain.updateKeysAfterDhRatchet(newChainKey: finalSenderKey) else {
                return .failure(.generic("Failed to update sending chain"))
            }

            // Create receiving chain
            let receivingChainResult = ProtocolChainStep.create(
                stepType: .receiving,
                initialChainKey: finalReceiverKey,
                initialDhPrivateKey: persistentDhPrivateKey,
                initialDhPublicKey: persistentDhPublicKey!,
                cacheWindowSize: ratchetConfig.cacheWindowSize
            )

            guard case .success(let newReceivingChain) = receivingChainResult else {
                return .failure(.generic("Failed to create receiving chain"))
            }

            // Update connection state
            CryptographicHelpers.secureWipe(&rootKey)
            rootKey = Data(newRootKey)
            receivingChain = newReceivingChain
            peerDhPublicKey = Data(initialPeerDhPublicKey)

            // Derive metadata encryption key
            _ = deriveMetadataEncryptionKey()

            return .success(.value)
        } catch {
            return .failure(.generic("DH ratchet failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Prepare Next Send Message
    /// Prepares a message key for the next outgoing message
    /// Migrated from: PrepareNextSendMessage()
    public func prepareNextSendMessage() -> Result<(ratchetKey: RatchetChainKey, includeDhKey: Bool, dhPublicKey: Data?), ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        // Check session timeout
        if Date().timeIntervalSince(createdAt) > sessionTimeout {
            return .failure(.generic("Session has expired"))
        }

        // Get current sending index
        guard case .success(let currentIndex) = sendingChain.getCurrentIndex() else {
            return .failure(.generic("Failed to get current sending index"))
        }

        // Check if we should perform DH ratchet
        let shouldRatchet = ratchetConfig.shouldRatchet(
            currentIndex: currentIndex + 1,
            lastRatchetTime: lastRatchetTime,
            receivedNewDhKey: receivedNewDhKey
        )

        if shouldRatchet {
            _ = performDhRatchet(isSender: true)
        }

        // Derive key for next message
        let nextIndex = currentIndex + 1
        let keyResult = sendingChain.getOrDeriveKeyFor(targetIndex: nextIndex)

        guard case .success(let ratchetKey) = keyResult else {
            if case .failure(let error) = keyResult {
                return .failure(error)
            }
            return .failure(.generic("Failed to derive sending key"))
        }

        // Update sending index
        _ = sendingChain.setCurrentIndex(nextIndex)

        let dhPublicKey = shouldRatchet ? sendingDhPublicKey : nil
        return .success((ratchetKey, shouldRatchet, dhPublicKey))
    }

    // MARK: - Process Received Message
    /// Processes a received message at a specific ratchet index
    /// Migrated from: ProcessReceivedMessage()
    public func processReceivedMessage(receivedIndex: UInt32) -> Result<RatchetChainKey, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        // Check session timeout
        if Date().timeIntervalSince(createdAt) > sessionTimeout {
            return .failure(.generic("Session has expired"))
        }

        guard let receivingChain = receivingChain else {
            return .failure(.generic("Receiving chain not initialized"))
        }

        // Try to recover from skipped messages
        if case .success(let recoveredKey) = ratchetRecovery.tryRecoverMessageKey(messageIndex: receivedIndex),
           case .some(let key) = recoveredKey {
            return .success(key)
        }

        // Get current receiving index
        guard case .success(let currentIndex) = receivingChain.getCurrentIndex() else {
            return .failure(.generic("Failed to get current receiving index"))
        }

        // Handle skipped messages
        if receivedIndex > currentIndex + 1 {
            guard case .success(let chainKey) = receivingChain.getCurrentChainKey() else {
                return .failure(.generic("Failed to get current chain key"))
            }

            _ = ratchetRecovery.storeSkippedMessageKeys(
                currentChainKey: chainKey,
                fromIndex: currentIndex + 1,
                toIndex: receivedIndex
            )
        }

        // Derive key for received message index
        let keyResult = receivingChain.getOrDeriveKeyFor(targetIndex: receivedIndex)
        guard case .success(let ratchetKey) = keyResult else {
            return .failure(.generic("Failed to derive receiving key"))
        }

        // Update receiving index
        _ = receivingChain.setCurrentIndex(receivedIndex)

        // Cleanup old recovery keys
        if receivedIndex > 1000 {
            ratchetRecovery.cleanupOldKeys(beforeIndex: receivedIndex - 1000)
        }

        return .success(ratchetKey)
    }

    // MARK: - Perform Receiving Ratchet
    /// Performs a DH ratchet when receiving a new DH public key from peer
    /// Migrated from: PerformReceivingRatchet()
    public func performReceivingRatchet(receivedDhPublicKey: Data) -> Result<Unit, ProtocolFailure> {
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

        // Perform DH ratchet if conditions are met
        guard let receivingChain = receivingChain else {
            return .failure(.generic("Receiving chain not initialized"))
        }

        guard case .success(let currentIndex) = receivingChain.getCurrentIndex() else {
            return .failure(.generic("Failed to get receiving index"))
        }

        let shouldRatchet = isFirstReceivingRatchet ||
            ratchetConfig.shouldRatchet(currentIndex: currentIndex + 1, lastRatchetTime: lastRatchetTime, receivedNewDhKey: receivedNewDhKey)

        if shouldRatchet {
            isFirstReceivingRatchet = false
            return performDhRatchet(isSender: false, receivedDhPublicKey: receivedDhPublicKey)
        }

        return .success(.value)
    }

    // MARK: - Perform DH Ratchet
    /// Performs the Double Ratchet algorithm DH step
    private func performDhRatchet(isSender: Bool, receivedDhPublicKey: Data? = nil) -> Result<Unit, ProtocolFailure> {
        guard let peerKey = isSender ? peerDhPublicKey : receivedDhPublicKey else {
            return .failure(.generic("Peer DH public key not available"))
        }

        do {
            let x25519 = X25519KeyExchange()

            // Perform DH key agreement
            let dhSecret = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: sendingDhPrivateKey,
                publicKeyBytes: peerKey
            )

            // Derive new root key and chain key using HKDF
            let dhRatchetInfo = Data("ecliptix-dh-ratchet".utf8)
            let derived = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: dhSecret,
                salt: rootKey,
                info: dhRatchetInfo,
                outputByteCount: 64 // 32 for root key + 32 for chain key
            )

            let newRootKey = derived.prefix(32)
            let newChainKey = derived.suffix(32)

            // Update root key
            CryptographicHelpers.secureWipe(&rootKey)
            rootKey = Data(newRootKey)

            if isSender {
                // Generate new DH key pair for sending
                let (newPrivateKey, newPublicKey) = x25519.generateKeyPair()
                let newPrivateKeyBytes = x25519.privateKeyToBytes(newPrivateKey)
                let newPublicKeyBytes = x25519.publicKeyToBytes(newPublicKey)

                // Update sending chain
                _ = sendingChain.updateKeysAfterDhRatchet(
                    newChainKey: Data(newChainKey),
                    newDhPrivateKey: newPrivateKeyBytes,
                    newDhPublicKey: newPublicKeyBytes
                )

                // Update stored DH keys
                CryptographicHelpers.secureWipe(&sendingDhPrivateKey)
                sendingDhPrivateKey = newPrivateKeyBytes
                sendingDhPublicKey = newPublicKeyBytes
            } else {
                // Update receiving chain
                _ = receivingChain?.updateKeysAfterDhRatchet(newChainKey: Data(newChainKey))
                peerDhPublicKey = Data(peerKey)
            }

            // Update ratchet state
            lastRatchetTime = Date()
            receivedNewDhKey = false
            replayProtection.onRatchetRotation()

            // Derive new metadata encryption key
            _ = deriveMetadataEncryptionKey()

            return .success(.value)
        } catch {
            return .failure(.generic("DH ratchet failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Get Metadata Encryption Key
    /// Gets the metadata encryption key derived from root key
    /// Migrated from: GetMetadataEncryptionKey()
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

    // MARK: - Check Replay Protection
    /// Checks if a message nonce has been seen before (replay attack prevention)
    /// Migrated from: CheckReplayProtection()
    public func checkReplayProtection(nonce: Data, messageIndex: UInt32) -> Result<Unit, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        return replayProtection.checkAndRecordMessage(
            nonce: nonce,
            messageIndex: UInt64(messageIndex),
            chainIndex: 0
        )
    }

    // MARK: - Get Current Sender DH Public Key
    /// Gets our current sending DH public key to include in messages
    public func getCurrentSenderDhPublicKey() -> Result<Data?, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        return .success(Data(sendingDhPublicKey))
    }

    // MARK: - Get Sending Chain Index
    public func getSendingChainIndex() -> Result<UInt32, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        return sendingChain.getCurrentIndex()
    }

    // MARK: - Get Receiving Chain Index
    public func getReceivingChainIndex() -> Result<UInt32, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        guard let chain = receivingChain else {
            return .failure(.generic("No receiving chain"))
        }

        return chain.getCurrentIndex()
    }

    // MARK: - Generate Nonce
    /// Generates a unique nonce for message encryption
    /// Migrated from: GenerateNextNonce()
    public func generateNonce() -> Data {
        lock.lock()
        defer { lock.unlock() }

        nonceCounter += 1
        var nonce = Data(count: CryptographicConstants.aesGcmNonceSize)

        // First 8 bytes: counter (little-endian)
        var counter = nonceCounter.littleEndian
        withUnsafeBytes(of: &counter) { buffer in
            nonce.replaceSubrange(0..<8, with: buffer)
        }

        // Last 4 bytes: random
        let randomBytes = CryptographicHelpers.generateRandomBytes(count: 4)
        nonce.replaceSubrange(8..<12, with: randomBytes)

        return nonce
    }

    // MARK: - Set Peer Bundle
    public func setPeerBundle(_ bundle: PublicKeyBundle) -> Result<Unit, ProtocolFailure> {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else {
            return .failure(.generic("Connection has been disposed"))
        }

        peerBundle = bundle
        return .success(.value)
    }

    // MARK: - Get Peer Bundle
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

    // MARK: - Private Helpers

    private func deriveMetadataEncryptionKey() -> Result<Data, ProtocolFailure> {
        do {
            let key = try HKDFKeyDerivation.deriveMetadataEncryptionKey(from: rootKey)
            metadataEncryptionKey = key
            return .success(key)
        } catch {
            return .failure(.generic("Failed to derive metadata encryption key: \(error.localizedDescription)"))
        }
    }

    // MARK: - Dispose
    public func dispose() {
        lock.lock()
        defer { lock.unlock() }

        guard !isDisposed else { return }
        isDisposed = true

        sendingChain.dispose()
        receivingChain?.dispose()
        replayProtection.dispose()
        ratchetRecovery.dispose()

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

// MARK: - Debug Description
extension ProtocolConnection: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "ProtocolConnection(id: \(id), isInitiator: \(isInitiator), hasReceivingChain: \(receivingChain != nil))"
    }
}
