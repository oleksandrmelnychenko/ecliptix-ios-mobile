import EcliptixCore
import EcliptixProto
import EcliptixSecurity
import Foundation
import GRPCCore

extension ProtocolConnectionManager {

    public func createConnection(
        connectId: UInt32,
        appInstanceId: UUID,
        deviceId: UUID,
        membershipId: UUID?,
        identityPrivateKey: Data? = nil,
        deviceServiceClient: DeviceServiceClient
    ) async throws {

        Log.info("[ProtocolConnectionManager] Creating connection \(connectId)")

        Log.warning("[ProtocolConnectionManager] Connection creation not fully implemented - needs IdentityKeys API")

        Log.info("[ProtocolConnectionManager] [WARNING] Connection \(connectId) created (stub)")
    }

    public func establishSecureChannel(
        connectId: UInt32,
        deviceServiceClient: DeviceServiceClient,
        exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect
    ) async throws -> Data {

        Log.info("[ProtocolConnectionManager] Establishing secure channel - ConnectId: \(connectId)")

        guard getConnection(connectId) != nil else {
            throw ProtocolConnectionError.connectionNotFound(connectId)
        }

        let aliceBundle = try x3dhService.generatePreKeyBundle()

        let alicePublicBundle = X3DHPublicKeyBundle(
            identityPublicKey: aliceBundle.identityPublicKey,
            signedPreKeyId: aliceBundle.signedPreKeyId,
            signedPreKeyPublicKey: aliceBundle.signedPreKeyPublicKey,
            signedPreKeySignature: aliceBundle.signedPreKeySignature,
            ephemeralPublicKey: aliceBundle.ephemeralPublicKey
        )

        let encoder = JSONEncoder()
        let x3dhData = try encoder.encode(alicePublicBundle)

        var requestEnvelope = Common_SecureEnvelope()
        requestEnvelope.encryptedPayload = x3dhData
        requestEnvelope.metaData = Data()
        requestEnvelope.resultCode = Data()

        Log.info("[ProtocolConnectionManager] Sending X3DH bundle to server - ConnectId: \(connectId)")

        let responseEnvelope = try await deviceServiceClient.establishSecureChannel(
            envelope: requestEnvelope,
            exchangeType: exchangeType
        )

        guard !responseEnvelope.resultCode.isEmpty else {
            Log.error("[ProtocolConnectionManager] Server returned empty result code")
            throw ProtocolConnectionError.x3dhExchangeFailed("Server error: empty result code")
        }

        Log.info("[ProtocolConnectionManager] Received server X3DH bundle - ConnectId: \(connectId)")

        let decoder = JSONDecoder()
        let bobBundle = try decoder.decode(X3DHPublicKeyBundle.self, from: responseEnvelope.encryptedPayload)

        let bobIdentityValidation = DHValidator.validateX25519PublicKey(bobBundle.identityPublicKey)
        guard case .success = bobIdentityValidation else {
            Log.error("[ProtocolConnectionManager] Server identity key validation failed")
            throw ProtocolConnectionError.x3dhExchangeFailed("Invalid server identity key")
        }

        let bobSPKValidation = DHValidator.validateX25519PublicKey(bobBundle.signedPreKeyPublicKey)
        guard case .success = bobSPKValidation else {
            Log.error("[ProtocolConnectionManager] Server signed pre-key validation failed")
            throw ProtocolConnectionError.x3dhExchangeFailed("Invalid server signed pre-key")
        }

        let bobEPKValidation = DHValidator.validateX25519PublicKey(bobBundle.ephemeralPublicKey)
        guard case .success = bobEPKValidation else {
            Log.error("[ProtocolConnectionManager] Server ephemeral key validation failed")
            throw ProtocolConnectionError.x3dhExchangeFailed("Invalid server ephemeral key")
        }

        Log.info("[ProtocolConnectionManager] [OK] All server public keys validated (DHValidator)")

        let sharedSecret = try x3dhService.performInitiatorKeyAgreement(
            bobsBundle: bobBundle,
            aliceIdentityPrivate: aliceBundle.identityPrivateKey,
            aliceEphemeralPrivate: aliceBundle.ephemeralPrivateKey
        )

        Log.info("[ProtocolConnectionManager] [OK] X3DH key agreement complete - shared secret: \(sharedSecret.count) bytes")

        let (rootKey, sendingChainKey, _) = try x3dhService.deriveInitialKeys(from: sharedSecret)

        let doubleRatchetResult = ProtocolConnection.create(
            connectionId: connectId,
            isInitiator: true,
            initialRootKey: rootKey,
            initialChainKey: sendingChainKey
        )

        guard case .success(let doubleRatchet) = doubleRatchetResult else {
            if case .failure(let error) = doubleRatchetResult {
                throw ProtocolConnectionError.x3dhExchangeFailed("Failed to create DoubleRatchet: \(error.message)")
            }
            throw ProtocolConnectionError.x3dhExchangeFailed("Failed to create DoubleRatchet")
        }

        updateConnection(connectId, doubleRatchet: doubleRatchet)

        Log.info("[ProtocolConnectionManager] [OK] Double Ratchet initialized - ConnectId: \(connectId)")
        Log.info("[ProtocolConnectionManager] [OK] Secure channel established successfully - ConnectId: \(connectId)")

        return try serializeSessionState(connectId: connectId)
    }

    public func restoreConnection(
        connectId: UInt32,
        stateData: Data,
        membershipId: UUID,
        deviceServiceClient: DeviceServiceClient
    ) async throws {

        Log.info("[ProtocolConnectionManager] Restoring connection - ConnectId: \(connectId)")

        let restoreRequest = Device_RestoreChannelRequest()

        let restoreResponse = try await deviceServiceClient.restoreSecureChannel(
            request: restoreRequest
        )

        if restoreResponse.status != .sessionRestored {
            Log.error("[ProtocolConnectionManager] Session restore failed: \(restoreResponse.status)")
            throw ProtocolConnectionError.sessionRestoreFailed("Server status: \(restoreResponse.status)")
        }

        Log.info("[ProtocolConnectionManager] Session restored - Server S:\(restoreResponse.sendingChainLength) R:\(restoreResponse.receivingChainLength)")
        Log.warning("[ProtocolConnectionManager] Session restoration not fully implemented")
        Log.info("[ProtocolConnectionManager] [WARNING] Connection restored (stub) - ConnectId: \(connectId)")
    }

    private func serializeSessionState(connectId: UInt32) throws -> Data {
        guard let session = getConnection(connectId) else {
            throw ProtocolConnectionError.connectionNotFound(connectId)
        }

        guard let doubleRatchet = session.doubleRatchet else {
            throw ProtocolConnectionError.noDoubleRatchet(connectId)
        }

        guard case .success(let ratchetState) = doubleRatchet.toProtoState() else {
            throw ProtocolConnectionError.sessionRestoreFailed("Failed to export ratchet state")
        }

        let identityKeysState = try session.identityKeys.toProtoState()

        let sessionState = ProtocolSessionState(
            connectId: connectId,
            identityKeysState: identityKeysState,
            ratchetState: ratchetState,
            createdAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let serializedData = try encoder.encode(sessionState)

        Log.info("[ProtocolConnectionManager] [OK] Serialized session state - ConnectId: \(connectId), size: \(serializedData.count) bytes")
        return serializedData
    }

    private func deserializeSessionState(stateData: Data) throws -> (IdentityKeys, ProtocolConnection) {

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessionState = try decoder.decode(ProtocolSessionState.self, from: stateData)

        let identityKeys = try IdentityKeys.fromProtoState(sessionState.identityKeysState)

        guard let ratchetState = sessionState.ratchetState else {
            throw ProtocolConnectionError.sessionRestoreFailed("Missing ratchet state")
        }

        guard case .success(let doubleRatchet) = ProtocolConnection.fromProtoState(
            connectionId: sessionState.connectId,
            state: ratchetState
        ) else {
            throw ProtocolConnectionError.sessionRestoreFailed("Failed to restore DoubleRatchet")
        }

        Log.info("[ProtocolConnectionManager] [OK] Deserialized session state - ConnectId: \(sessionState.connectId)")
        return (identityKeys, doubleRatchet)
    }
}
public enum ProtocolConnectionError: Error, LocalizedError {
    case connectionNotFound(UInt32)
    case noDoubleRatchet(UInt32)
    case x3dhExchangeFailed(String)
    case sessionRestoreFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionNotFound(let connectId):
            return "Protocol connection not found: \(connectId)"
        case .noDoubleRatchet(let connectId):
            return "DoubleRatchet not initialized for connection: \(connectId)"
        case .x3dhExchangeFailed(let message):
            return "X3DH key exchange failed: \(message)"
        case .sessionRestoreFailed(let message):
            return "Session restore failed: \(message)"
        }
    }
}

public enum PubKeyExchangeType: Int, Hashable, Sendable {
    case dataCenterEphemeralConnect = 0
    case dataCenterPersistentConnect = 1
    case peerToPeerConnect = 2
}
