import Foundation
import EcliptixCore
import EcliptixSecurity

// MARK: - Protocol Connection Manager
/// Manages protocol sessions (DoubleRatchet + X3DH) by connection ID
/// Migrated from: NetworkProvider connection management (ConcurrentDictionary<uint, EcliptixProtocolSystem>)
public final class ProtocolConnectionManager {

    // MARK: - Properties

    /// Active protocol connections indexed by connectId
    private var connections: [UInt32: ProtocolSession] = [:]
    private let connectionsLock = NSLock()

    // MARK: - Types

    /// Represents a protocol session with Double Ratchet
    public struct ProtocolSession {
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

    // MARK: - Initialization

    public init() {}

    // MARK: - Connection Management

    /// Adds a new protocol session
    /// Migrated from: InitiateEcliptixProtocolSystem()
    public func addConnection(connectId: UInt32, identityKeys: IdentityKeys, doubleRatchet: DoubleRatchet? = nil) {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        let session = ProtocolSession(
            connectId: connectId,
            identityKeys: identityKeys,
            doubleRatchet: doubleRatchet
        )
        connections[connectId] = session

        Log.info("[ProtocolConnectionManager] Added connection \(connectId)")
    }

    /// Gets a protocol session by connectId
    public func getConnection(_ connectId: UInt32) -> ProtocolSession? {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        return connections[connectId]
    }

    /// Updates an existing protocol session
    public func updateConnection(_ connectId: UInt32, doubleRatchet: DoubleRatchet) {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        guard var session = connections[connectId] else {
            Log.warning("[ProtocolConnectionManager] Cannot update non-existent connection \(connectId)")
            return
        }

        session.doubleRatchet = doubleRatchet
        connections[connectId] = session

        Log.debug("[ProtocolConnectionManager] Updated connection \(connectId)")
    }

    /// Removes a protocol session
    /// Migrated from: CleanupStreamProtocolAsync()
    public func removeConnection(_ connectId: UInt32) {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        connections.removeValue(forKey: connectId)
        Log.info("[ProtocolConnectionManager] Removed connection \(connectId)")
    }

    /// Checks if a connection exists
    public func hasConnection(_ connectId: UInt32) -> Bool {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        return connections[connectId] != nil
    }

    /// Gets all active connection IDs
    public func getAllConnectionIds() -> [UInt32] {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        return Array(connections.keys)
    }

    /// Removes all connections
    public func removeAll() {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        let count = connections.count
        connections.removeAll()

        Log.info("[ProtocolConnectionManager] Removed all \(count) connections")
    }

    // MARK: - Encryption/Decryption

    /// Encrypts plain data using the protocol session
    /// Migrated from: protocolSystem.ProduceOutboundEnvelope(plainBuffer)
    public func encryptOutbound(_ connectId: UInt32, plainData: Data) -> Result<SecureEnvelope, ProtocolFailure> {
        connectionsLock.lock()
        guard var session = connections[connectId] else {
            connectionsLock.unlock()
            return .failure(.connectionNotFound("No protocol connection for connectId: \(connectId)"))
        }
        connectionsLock.unlock()

        guard var ratchet = session.doubleRatchet else {
            return .failure(.noDoubleRatchet("Double Ratchet not initialized for connectId: \(connectId)"))
        }

        Log.info("[ProtocolConnectionManager] Encrypting outbound for connection \(connectId), plainDataSize: \(plainData.count)")

        // Log ratchet state before encryption
        Log.debug("[ProtocolConnectionManager] Before encryption - Sending: \(ratchet.sendingChainIndex), Receiving: \(ratchet.receivingChainIndex)")

        // Encrypt with Double Ratchet
        let result = ratchet.encryptMessage(plaintext: plainData, associatedData: Data())

        // Update session with new ratchet state
        connectionsLock.lock()
        session.doubleRatchet = ratchet
        connections[connectId] = session
        connectionsLock.unlock()

        switch result {
        case .success(let envelope):
            Log.info("[ProtocolConnectionManager] Encryption succeeded for connection \(connectId)")
            Log.debug("[ProtocolConnectionManager] After encryption - Sending: \(ratchet.sendingChainIndex)")
            return .success(envelope)

        case .failure(let error):
            Log.error("[ProtocolConnectionManager] Encryption failed for connection \(connectId): \(error.message)")
            return .failure(error)
        }
    }

    /// Decrypts inbound SecureEnvelope using the protocol session
    /// Migrated from: protocolSystem.ProcessInboundEnvelope(inboundPayload)
    public func decryptInbound(_ connectId: UInt32, envelope: SecureEnvelope) -> Result<Data, ProtocolFailure> {
        connectionsLock.lock()
        guard var session = connections[connectId] else {
            connectionsLock.unlock()
            return .failure(.connectionNotFound("No protocol connection for connectId: \(connectId)"))
        }
        connectionsLock.unlock()

        guard var ratchet = session.doubleRatchet else {
            return .failure(.noDoubleRatchet("Double Ratchet not initialized for connectId: \(connectId)"))
        }

        Log.info("[ProtocolConnectionManager] Decrypting inbound for connection \(connectId)")

        // Log ratchet state before decryption
        Log.debug("[ProtocolConnectionManager] Before decryption - Sending: \(ratchet.sendingChainIndex), Receiving: \(ratchet.receivingChainIndex)")

        // Decrypt with Double Ratchet
        let result = ratchet.decryptMessage(envelope: envelope, associatedData: Data())

        // Update session with new ratchet state
        connectionsLock.lock()
        session.doubleRatchet = ratchet
        connections[connectId] = session
        connectionsLock.unlock()

        switch result {
        case .success(let plaintext):
            Log.info("[ProtocolConnectionManager] Decryption succeeded for connection \(connectId), plaintextSize: \(plaintext.count)")
            Log.debug("[ProtocolConnectionManager] After decryption - Receiving: \(ratchet.receivingChainIndex)")
            return .success(plaintext)

        case .failure(let error):
            Log.error("[ProtocolConnectionManager] Decryption failed for connection \(connectId): \(error.message)")
            return .failure(error)
        }
    }
}
