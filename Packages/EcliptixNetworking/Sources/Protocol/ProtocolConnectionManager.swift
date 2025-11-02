import EcliptixCore
import EcliptixSecurity
import Foundation

public actor ProtocolConnectionManager {

    internal var connections: [UInt32: ProtocolSession] = [:]

    public struct ProtocolSession: @unchecked Sendable {
        public let connectId: UInt32
        public let identityKeys: IdentityKeys
        public var doubleRatchet: DoubleRatchet?
        public let createdAt: Date

        public init(connectId: UInt32, identityKeys: IdentityKeys, doubleRatchet: DoubleRatchet? = nil) {
            self.connectId = connectId
            self.identityKeys = identityKeys
            self.doubleRatchet = doubleRatchet
            self.createdAt = Date()
        }
    }

    internal let x3dhService: X3DHKeyExchange

    public init(x3dhService: X3DHKeyExchange = X3DHKeyExchange()) {
        self.x3dhService = x3dhService
    }

    public func addConnection(connectId: UInt32, identityKeys: IdentityKeys, doubleRatchet: DoubleRatchet? = nil) {
        let session = ProtocolSession(
            connectId: connectId,
            identityKeys: identityKeys,
            doubleRatchet: doubleRatchet
        )
        connections[connectId] = session

        Log.info("[ProtocolConnectionManager] Added connection \(connectId)")
    }

    public func getConnection(_ connectId: UInt32) -> ProtocolSession? {
        return connections[connectId]
    }

    public func updateConnection(_ connectId: UInt32, doubleRatchet: DoubleRatchet) {
        guard var session = connections[connectId] else {
            Log.warning("[ProtocolConnectionManager] Cannot update non-existent connection \(connectId)")
            return
        }

        session.doubleRatchet = doubleRatchet
        connections[connectId] = session

        Log.debug("[ProtocolConnectionManager] Updated connection \(connectId)")
    }

    public func removeConnection(_ connectId: UInt32) {
        connections.removeValue(forKey: connectId)
        Log.info("[ProtocolConnectionManager] Removed connection \(connectId)")
    }

    public func hasConnection(_ connectId: UInt32) -> Bool {
        return connections[connectId] != nil
    }

    public func getAllConnectionIds() -> [UInt32] {
        return Array(connections.keys)
    }

    public func removeAll() {
        let count = connections.count
        connections.removeAll()

        Log.info("[ProtocolConnectionManager] Removed all \(count) connections")
    }

    public func encryptOutbound(_ connectId: UInt32, plainData: Data) -> Result<SecureEnvelope, ProtocolFailure> {
        guard var session = connections[connectId] else {
            return .failure(.connectionNotFound("No protocol connection for connectId: \(connectId)"))
        }

        guard let ratchet = session.doubleRatchet else {
            return .failure(.noDoubleRatchet("Double Ratchet not initialized for connectId: \(connectId)"))
        }

        Log.info("[ProtocolConnectionManager] Encrypting outbound for connection \(connectId), plainDataSize: \(plainData.count)")

        do {
            let sendingIndex = try ratchet.getSendingChainIndex()
            let receivingIndex = try ratchet.getReceivingChainIndex()
            Log.debug("[ProtocolConnectionManager] Before encryption - Sending: \(sendingIndex), Receiving: \(receivingIndex)")
        } catch {
            Log.warning("[ProtocolConnectionManager] Failed to get chain indices: \(error.localizedDescription)")
        }

        guard case .success(let (ratchetKey, includeDhKey, dhPublicKey)) = ratchet.prepareNextSendMessage() else {
            return .failure(.generic("Failed to prepare next send message"))
        }

        var messageKey: Data?
        var headerKey: Data?
        do {
            try ratchetKey.withKeyMaterial { keyMaterial in

                let msgKey = try HKDFKeyDerivation.deriveKey(
                    inputKeyMaterial: keyMaterial,
                    salt: nil,
                    info: Data(CryptographicConstants.msgInfo),
                    outputByteCount: CryptographicConstants.aesKeySize
                )
                messageKey = msgKey

                let hdrKey = try HKDFKeyDerivation.deriveKey(
                    inputKeyMaterial: keyMaterial,
                    salt: nil,
                    info: Data("header-enc".utf8),
                    outputByteCount: CryptographicConstants.aesKeySize
                )
                headerKey = hdrKey
            }
        } catch {
            return .failure(.generic("Failed to derive keys: \(error.localizedDescription)"))
        }

        guard let msgKey = messageKey, let hdrKey = headerKey else {
            return .failure(.generic("Failed to execute key derivation"))
        }

        let messageNonce = CryptographicHelpers.generateRandomNonce(size: CryptographicConstants.aesGcmNonceSize)
        let headerNonce = CryptographicHelpers.generateRandomNonce(size: CryptographicConstants.aesGcmNonceSize)

        let ratchetIndex: UInt32
        do {
            ratchetIndex = try ratchet.getSendingChainIndex()
        } catch {
            return .failure(.generic("Failed to get sending chain index: \(error.localizedDescription)"))
        }

        let requestId: UInt32 = UInt32(Date().timeIntervalSince1970 * 1000) % UInt32.max

        let associatedData = Data()
        let envelopeResult = EnvelopeBuilder.createRequestEnvelope(
            requestId: requestId,
            payload: plainData,
            messageKey: msgKey,
            headerKey: hdrKey,
            nonce: messageNonce,
            headerNonce: headerNonce,
            ratchetIndex: ratchetIndex,
            channelKeyId: nil,
            dhPublicKey: includeDhKey ? dhPublicKey : nil,
            associatedData: associatedData
        )

        guard case .success(let envelope) = envelopeResult else {
            if case .failure(let error) = envelopeResult {
                return .failure(error)
            }
            return .failure(.generic("Failed to create request envelope"))
        }

        session.doubleRatchet = ratchet
        connections[connectId] = session

        Log.info("[ProtocolConnectionManager] Successfully encrypted outbound for connection \(connectId)")

        return .success(envelope)
    }

    public func decryptInbound(_ connectId: UInt32, envelope: SecureEnvelope) -> Result<Data, ProtocolFailure> {
        guard var session = connections[connectId] else {
            return .failure(.connectionNotFound("No protocol connection for connectId: \(connectId)"))
        }

        guard let ratchet = session.doubleRatchet else {
            return .failure(.noDoubleRatchet("Double Ratchet not initialized for connectId: \(connectId)"))
        }

        Log.info("[ProtocolConnectionManager] Decrypting inbound for connection \(connectId)")

        do {
            let sendingIndex = try ratchet.getSendingChainIndex()
            let receivingIndex = try ratchet.getReceivingChainIndex()
            Log.debug("[ProtocolConnectionManager] Before decryption - Sending: \(sendingIndex), Receiving: \(receivingIndex)")
        } catch {
            Log.warning("[ProtocolConnectionManager] Failed to get chain indices: \(error.localizedDescription)")
        }

        guard case .success(let metadata) = EnvelopeBuilder.parseEnvelopeMetadata(from: envelope.metaData) else {
            return .failure(.decode("Failed to parse envelope metadata"))
        }

        let receivedIndex = UInt32(metadata.ratchetIndex)

        guard case .success(let ratchetKey) = ratchet.processReceivedMessage(receivedIndex: receivedIndex) else {
            return .failure(.generic("Failed to process received message at index \(receivedIndex)"))
        }

        var messageKey: Data?
        var headerKey: Data?
        do {
            try ratchetKey.withKeyMaterial { keyMaterial in

                let msgKey = try HKDFKeyDerivation.deriveKey(
                    inputKeyMaterial: keyMaterial,
                    salt: nil,
                    info: Data(CryptographicConstants.msgInfo),
                    outputByteCount: CryptographicConstants.aesKeySize
                )
                messageKey = msgKey

                let hdrKey = try HKDFKeyDerivation.deriveKey(
                    inputKeyMaterial: keyMaterial,
                    salt: nil,
                    info: Data("header-enc".utf8),
                    outputByteCount: CryptographicConstants.aesKeySize
                )
                headerKey = hdrKey
            }
        } catch {
            return .failure(.generic("Failed to derive keys: \(error.localizedDescription)"))
        }

        guard let msgKey = messageKey, let hdrKey = headerKey else {
            return .failure(.generic("Failed to execute key derivation"))
        }

        let associatedData = Data()
        let decryptResult = EnvelopeBuilder.decryptResponseEnvelope(
            envelope: envelope,
            messageKey: msgKey,
            headerKey: hdrKey,
            associatedData: associatedData
        )

        guard case .success(let (_, payload, resultCode)) = decryptResult else {
            if case .failure(let error) = decryptResult {
                return .failure(error)
            }
            return .failure(.generic("Failed to decrypt response envelope"))
        }

        if resultCode != .success {
            Log.warning("[ProtocolConnectionManager] Envelope result code indicates error: \(resultCode)")
        }

        session.doubleRatchet = ratchet
        connections[connectId] = session

        Log.info("[ProtocolConnectionManager] Successfully decrypted inbound for connection \(connectId), payloadSize: \(payload.count)")

        return .success(payload)
    }

    func establishSecureChannel(connectId: UInt32) async throws -> Data {
        Log.info("[ProtocolConnectionManager] Establishing secure channel - ConnectId: \(connectId)")

        let bundle = try x3dhService.generatePreKeyBundle()

        Log.info("[ProtocolConnectionManager] Generated pre-key bundle")

        let serverBundle = X3DHPublicKeyBundle(
            identityPublicKey: bundle.identityPublicKey,
            signedPreKeyId: bundle.signedPreKeyId,
            signedPreKeyPublicKey: bundle.signedPreKeyPublicKey,
            signedPreKeySignature: bundle.signedPreKeySignature,
            ephemeralPublicKey: bundle.ephemeralPublicKey
        )

        let sharedSecret = try x3dhService.performInitiatorKeyAgreement(
            bobsBundle: serverBundle,
            aliceIdentityPrivate: bundle.identityPrivateKey,
            aliceEphemeralPrivate: bundle.ephemeralPrivateKey
        )

        Log.info("[X3DH] Key agreement successful, shared secret length: \(sharedSecret.count)")

        let (rootKey, sendingChainKey, _) = try x3dhService.deriveInitialKeys(from: sharedSecret)

        Log.info("[X3DH] Derived initial keys - Root key, Sending chain, Receiving chain")

        let identityKeys = try IdentityKeys.create(oneTimeKeyCount: 10)

        Log.info("[ProtocolConnectionManager] Initializing DoubleRatchet with X3DH-derived keys")

        let ratchetResult = ProtocolConnection.create(
            connectionId: connectId,
            isInitiator: true,
            initialRootKey: rootKey,
            initialChainKey: sendingChainKey,
            ratchetConfig: .default
        )

        guard case .success(let doubleRatchet) = ratchetResult else {
            if case .failure(let error) = ratchetResult {
                throw error
            }
            throw ProtocolFailure.generic("Failed to initialize DoubleRatchet")
        }

        Log.info("[ProtocolConnectionManager] [OK] DoubleRatchet initialized successfully")

        let session = ProtocolSession(
            connectId: connectId,
            identityKeys: identityKeys,
            doubleRatchet: doubleRatchet
        )

        connections[connectId] = session

        Log.info("[ProtocolConnectionManager] [OK] Secure channel established - ConnectId: \(connectId)")

        return try serializeSessionState(session)
    }

    func restoreConnection(
        connectId: UInt32,
        stateData: Data,
        membershipId: UUID
    ) async throws {
        Log.info("[ProtocolConnectionManager] Restoring connection - ConnectId: \(connectId), DataSize: \(stateData.count)")

        let decoder = PropertyListDecoder()
        let sessionState = try decoder.decode(ProtocolSessionState.self, from: stateData)

        guard sessionState.connectId == connectId else {
            throw ProtocolFailure.generic("ConnectId mismatch in session state: expected \(connectId), got \(sessionState.connectId)")
        }

        let identityKeys = try IdentityKeys.fromProtoState(sessionState.identityKeysState)
        Log.info("[ProtocolConnectionManager] [OK] Identity keys restored")

        var doubleRatchet: DoubleRatchet? = nil
        if let ratchetState = sessionState.ratchetState {
            guard case .success(let ratchet) = ProtocolConnection.fromProtoState(
                connectionId: connectId,
                state: ratchetState,
                ratchetConfig: .default
            ) else {
                throw ProtocolFailure.generic("Failed to restore DoubleRatchet from state")
            }
            doubleRatchet = ratchet
            Log.info("[ProtocolConnectionManager] [OK] DoubleRatchet restored")
        }

        let session = ProtocolSession(
            connectId: connectId,
            identityKeys: identityKeys,
            doubleRatchet: doubleRatchet
        )

        connections[connectId] = session

        Log.info("[ProtocolConnectionManager] [OK] Connection restored successfully - ConnectId: \(connectId)")
    }

    func createConnection(
        connectId: UInt32,
        appInstanceId: UUID,
        deviceId: UUID,
        membershipId: UUID?,
        identityPrivateKey: Data? = nil
    ) async throws {
        Log.info("[ProtocolConnectionManager] Creating connection - ConnectId: \(connectId), Authenticated: \(membershipId != nil)")

        let identityKeys: IdentityKeys
        if let privateKeyData = identityPrivateKey, let membershipIdValue = membershipId {
            identityKeys = try IdentityKeys.createFromMasterKey(
                masterKey: privateKeyData,
                membershipId: membershipIdValue.uuidString,
                oneTimeKeyCount: 10
            )
            Log.info("[ProtocolConnectionManager] Created authenticated identity keys from master key")
        } else {

            identityKeys = try IdentityKeys.create(oneTimeKeyCount: 10)
            Log.info("[ProtocolConnectionManager] Generated new anonymous identity keys")
        }

        let session = ProtocolSession(
            connectId: connectId,
            identityKeys: identityKeys,
            doubleRatchet: nil
        )

        connections[connectId] = session

        Log.info("[ProtocolConnectionManager] [OK] Connection created - ConnectId: \(connectId)")
    }

    private func serializeSessionState(_ session: ProtocolSession) throws -> Data {
        Log.info("[ProtocolConnectionManager] Serializing session state - ConnectId: \(session.connectId)")

        let identityKeysState = try session.identityKeys.toProtoState()

        var ratchetState: RatchetState? = nil
        if let doubleRatchet = session.doubleRatchet {
            guard case .success(let state) = doubleRatchet.toProtoState() else {
                throw ProtocolFailure.generic("Failed to serialize DoubleRatchet state")
            }
            ratchetState = state
        }

        let sessionState = ProtocolSessionState(
            connectId: session.connectId,
            identityKeysState: identityKeysState,
            ratchetState: ratchetState,
            createdAt: session.createdAt
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(sessionState)

        Log.info("[ProtocolConnectionManager] [OK] Session state serialized - Size: \(data.count) bytes")

        return data
    }
}
