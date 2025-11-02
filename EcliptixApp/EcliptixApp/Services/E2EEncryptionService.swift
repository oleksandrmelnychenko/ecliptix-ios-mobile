import EcliptixCore
import EcliptixSecurity
import Foundation
import Observation

@MainActor
@Observable
public final class E2EEncryptionService {

    private let identityService: IdentityService
    private let x3dhKeyExchange: X3DHKeyExchange
    private var activeConnections: [UInt32: ProtocolConnection] = [:]

    public var isInitialized: Bool = false
    public var errorMessage: String?

    public init(identityService: IdentityService) {
        self.identityService = identityService
        self.x3dhKeyExchange = X3DHKeyExchange()

        Log.info("[E2EEncryptionService] Initialized")
    }

    public func establishSessionAsInitiator(
        connectionId: UInt32,
        peerPublicKeyBundle: X3DHPublicKeyBundle,
        ourMembershipId: String
    ) async -> Result<UInt32, E2EEncryptionError> {

        Log.info("[E2EEncryptionService] Establishing session as initiator for connection: \(connectionId)")

        do {

            guard let membershipUUID = UUID(uuidString: ourMembershipId) else {
                return .failure(.invalidMembershipId("Invalid membership ID format"))
            }

            guard let identityBundle = try await identityService.loadIdentityKeyBundle(membershipId: membershipUUID) else {
                return .failure(.identityKeysNotFound("No identity keys found for membership"))
            }

            let x25519 = X25519KeyExchange()
            let (ephemeralPrivate, _) = x25519.generateKeyPair()
            let ephemeralPrivateBytes = x25519.privateKeyToBytes(ephemeralPrivate)

            let sharedSecret = try x3dhKeyExchange.performInitiatorKeyAgreement(
                bobsBundle: peerPublicKeyBundle,
                aliceIdentityPrivate: identityBundle.identityPrivateKey,
                aliceEphemeralPrivate: ephemeralPrivateBytes
            )

            let (rootKey, sendingChainKey, receivingChainKey) = try x3dhKeyExchange.deriveInitialKeys(from: sharedSecret)

            let connectionResult = ProtocolConnection.create(
                connectionId: connectionId,
                isInitiator: true,
                initialRootKey: rootKey,
                initialChainKey: sendingChainKey
            )

            switch connectionResult {
            case .success(let connection):
                activeConnections[connectionId] = connection
                Log.info("[E2EEncryptionService] [OK] Session established as initiator for connection: \(connectionId)")
                return .success(connectionId)

            case .failure(let protocolFailure):
                return .failure(.protocolError("Failed to create connection: \(protocolFailure.message)"))
            }

        } catch let error as X3DHError {
            Log.error("[E2EEncryptionService] X3DH error: \(error.localizedDescription)")
            return .failure(.keyExchangeFailed(error.localizedDescription))

        } catch {
            Log.error("[E2EEncryptionService] Session establishment failed: \(error.localizedDescription)")
            return .failure(.unknown(error.localizedDescription))
        }
    }

    public func establishSessionAsResponder(
        connectionId: UInt32,
        peerPublicKeyBundle: X3DHPublicKeyBundle,
        ourMembershipId: String
    ) async -> Result<UInt32, E2EEncryptionError> {

        Log.info("[E2EEncryptionService] Establishing session as responder for connection: \(connectionId)")

        do {

            guard let membershipUUID = UUID(uuidString: ourMembershipId) else {
                return .failure(.invalidMembershipId("Invalid membership ID format"))
            }

            guard let identityBundle = try await identityService.loadIdentityKeyBundle(membershipId: membershipUUID) else {
                return .failure(.identityKeysNotFound("No identity keys found for membership"))
            }

            let x25519 = X25519KeyExchange()
            let (ephemeralPrivate, _) = x25519.generateKeyPair()
            let ephemeralPrivateBytes = x25519.privateKeyToBytes(ephemeralPrivate)

            let sharedSecret = try x3dhKeyExchange.performResponderKeyAgreement(
                alicesBundle: peerPublicKeyBundle,
                bobIdentityPrivate: identityBundle.identityPrivateKey,
                bobSignedPreKeyPrivate: identityBundle.signedPreKeyPrivateKey,
                bobEphemeralPrivate: ephemeralPrivateBytes
            )

            let (rootKey, sendingChainKey, receivingChainKey) = try x3dhKeyExchange.deriveInitialKeys(from: sharedSecret)

            let connectionResult = ProtocolConnection.create(
                connectionId: connectionId,
                isInitiator: false,
                initialRootKey: rootKey,
                initialChainKey: receivingChainKey
            )

            switch connectionResult {
            case .success(let connection):
                activeConnections[connectionId] = connection
                Log.info("[E2EEncryptionService] [OK] Session established as responder for connection: \(connectionId)")
                return .success(connectionId)

            case .failure(let protocolFailure):
                return .failure(.protocolError("Failed to create connection: \(protocolFailure.message)"))
            }

        } catch let error as X3DHError {
            Log.error("[E2EEncryptionService] X3DH error: \(error.localizedDescription)")
            return .failure(.keyExchangeFailed(error.localizedDescription))

        } catch {
            Log.error("[E2EEncryptionService] Session establishment failed: \(error.localizedDescription)")
            return .failure(.unknown(error.localizedDescription))
        }
    }

    public func encryptMessage(
        _ plaintext: Data,
        connectionId: UInt32
    ) async -> Result<Data, E2EEncryptionError> {

        guard let connection = activeConnections[connectionId] else {
            return .failure(.connectionNotFound("No active connection for ID: \(connectionId)"))
        }

        Log.debug("[E2EEncryptionService] Encrypting message for connection: \(connectionId)")

        let result = connection.encryptMessage(plaintext)

        switch result {
        case .success(let encryptedData):
            Log.debug("[E2EEncryptionService] [OK] Message encrypted (\(encryptedData.count) bytes)")
            return .success(encryptedData)

        case .failure(let protocolFailure):
            Log.error("[E2EEncryptionService] Encryption failed: \(protocolFailure.message)")
            return .failure(.encryptionFailed(protocolFailure.message))
        }
    }

    public func decryptMessage(
        _ ciphertext: Data,
        connectionId: UInt32
    ) async -> Result<Data, E2EEncryptionError> {

        guard let connection = activeConnections[connectionId] else {
            return .failure(.connectionNotFound("No active connection for ID: \(connectionId)"))
        }

        Log.debug("[E2EEncryptionService] Decrypting message for connection: \(connectionId)")

        let result = connection.decryptMessage(ciphertext)

        switch result {
        case .success(let decryptedData):
            Log.debug("[E2EEncryptionService] [OK] Message decrypted (\(decryptedData.count) bytes)")
            return .success(decryptedData)

        case .failure(let protocolFailure):
            Log.error("[E2EEncryptionService] Decryption failed: \(protocolFailure.message)")
            return .failure(.decryptionFailed(protocolFailure.message))
        }
    }

    public func getOurPublicKeyBundle(membershipId: String) async -> Result<X3DHPublicKeyBundle, E2EEncryptionError> {

        do {
            guard let membershipUUID = UUID(uuidString: membershipId) else {
                return .failure(.invalidMembershipId("Invalid membership ID format"))
            }

            guard let identityBundle = try await identityService.loadIdentityKeyBundle(membershipId: membershipUUID) else {
                return .failure(.identityKeysNotFound("No identity keys found"))
            }

            let x25519 = X25519KeyExchange()
            let (ephemeralPrivate, ephemeralPublic) = x25519.generateKeyPair()
            let ephemeralPublicBytes = x25519.publicKeyToBytes(ephemeralPublic)

            let publicKeyBundle = X3DHPublicKeyBundle(
                identityPublicKey: identityBundle.identityPublicKey,
                signedPreKeyId: identityBundle.signedPreKeyId,
                signedPreKeyPublicKey: identityBundle.signedPreKeyPublicKey,
                signedPreKeySignature: identityBundle.signedPreKeySignature,
                ephemeralPublicKey: ephemeralPublicBytes
            )

            return .success(publicKeyBundle)

        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }

    public func closeSession(connectionId: UInt32) {
        if let connection = activeConnections.removeValue(forKey: connectionId) {
            connection.dispose()
            Log.info("[E2EEncryptionService] Closed session for connection: \(connectionId)")
        }
    }

    public func closeAllSessions() {
        for (connectionId, connection) in activeConnections {
            connection.dispose()
            Log.info("[E2EEncryptionService] Closed session for connection: \(connectionId)")
        }
        activeConnections.removeAll()
    }
}

public enum E2EEncryptionError: LocalizedError {
    case invalidMembershipId(String)
    case identityKeysNotFound(String)
    case keyExchangeFailed(String)
    case connectionNotFound(String)
    case protocolError(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMembershipId(let message),
             .identityKeysNotFound(let message),
             .keyExchangeFailed(let message),
             .connectionNotFound(let message),
             .protocolError(let message),
             .encryptionFailed(let message),
             .decryptionFailed(let message),
             .unknown(let message):
            return message
        }
    }
}
