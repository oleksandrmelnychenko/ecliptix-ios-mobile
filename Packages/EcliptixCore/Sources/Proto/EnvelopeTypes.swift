import Foundation

// MARK: - Protocol Buffer Placeholder Types
/// These types will be replaced by generated Protocol Buffer code
/// Temporary implementations based on proto definitions

// MARK: - Envelope Result Code
/// Corresponds to EnvelopeResultCode in secure_envelope.proto
public enum EnvelopeResultCode: Int32, Codable {
    case success = 0

    // Client errors (1-9)
    case badRequest = 1
    case unauthorized = 2
    case forbidden = 3
    case notFound = 4
    case methodNotAllowed = 5
    case conflict = 6
    case rateLimited = 7
    case payloadTooLarge = 8

    // Server errors (10-19)
    case internalError = 10
    case serviceUnavailable = 11
    case gatewayTimeout = 12
    case insufficientStorage = 13

    // Crypto errors (20-29)
    case cryptoError = 20
    case invalidSignature = 21
    case expiredKey = 22
    case ratchetError = 23
    case decryptionFailed = 24

    // Network errors (30-39)
    case networkError = 30
    case connectionLost = 31
    case timeout = 32
}

// MARK: - Envelope Type
/// Corresponds to EnvelopeType in secure_envelope.proto
public enum EnvelopeType: Int32, Codable {
    case request = 0
    case response = 1
    case notification = 2
    case heartbeat = 3
    case errorResponse = 4
}

// MARK: - Envelope Metadata
/// Corresponds to EnvelopeMetadata in secure_envelope.proto
public struct EnvelopeMetadata: Codable {
    public var envelopeId: String
    public var channelKeyId: Data
    public var nonce: Data
    public var ratchetIndex: UInt32
    public var envelopeType: EnvelopeType
    public var correlationId: String?

    public init(
        envelopeId: String,
        channelKeyId: Data,
        nonce: Data,
        ratchetIndex: UInt32,
        envelopeType: EnvelopeType,
        correlationId: String? = nil
    ) {
        self.envelopeId = envelopeId
        self.channelKeyId = channelKeyId
        self.nonce = nonce
        self.ratchetIndex = ratchetIndex
        self.envelopeType = envelopeType
        self.correlationId = correlationId
    }

    /// Serializes to binary format (temporary implementation)
    public func toData() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    /// Deserializes from binary format (temporary implementation)
    public static func fromData(_ data: Data) throws -> EnvelopeMetadata {
        let decoder = JSONDecoder()
        return try decoder.decode(EnvelopeMetadata.self, from: data)
    }
}

// MARK: - Envelope Error
/// Corresponds to EnvelopeError in secure_envelope.proto
public struct EnvelopeError: Codable {
    public var errorCode: String
    public var errorMessage: String
    public var retryAfterSeconds: UInt32?
    public var occurredAt: Date

    public init(
        errorCode: String,
        errorMessage: String,
        retryAfterSeconds: UInt32? = nil,
        occurredAt: Date = Date()
    ) {
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.retryAfterSeconds = retryAfterSeconds
        self.occurredAt = occurredAt
    }

    /// Serializes to binary format (temporary implementation)
    public func toData() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
}

// MARK: - Secure Envelope
/// Corresponds to SecureEnvelope in secure_envelope.proto
public struct SecureEnvelope: Codable {
    public var metaData: Data                    // Encrypted EnvelopeMetadata
    public var encryptedPayload: Data
    public var resultCode: Data                  // 4-byte int32
    public var authenticationTag: Data?
    public var timestamp: Date
    public var errorDetails: Data?
    public var headerNonce: Data                 // 12 bytes for header decryption
    public var dhPublicKey: Data?                // DH public key for ratchet

    public init(
        metaData: Data,
        encryptedPayload: Data,
        resultCode: Data,
        authenticationTag: Data? = nil,
        timestamp: Date = Date(),
        errorDetails: Data? = nil,
        headerNonce: Data,
        dhPublicKey: Data? = nil
    ) {
        self.metaData = metaData
        self.encryptedPayload = encryptedPayload
        self.resultCode = resultCode
        self.authenticationTag = authenticationTag
        self.timestamp = timestamp
        self.errorDetails = errorDetails
        self.headerNonce = headerNonce
        self.dhPublicKey = dhPublicKey
    }

    /// Serializes to binary format (temporary implementation)
    public func toData() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    /// Deserializes from binary format (temporary implementation)
    public static func fromData(_ data: Data) throws -> SecureEnvelope {
        let decoder = JSONDecoder()
        return try decoder.decode(SecureEnvelope.self, from: data)
    }
}

// MARK: - Protocol State Types
/// These types correspond to protocol_state.proto

// MARK: - Ratchet State
/// Corresponds to RatchetState in protocol_state.proto
public struct RatchetState: Codable {
    public var isInitiator: Bool
    public var createdAt: Date
    public var nonceCounter: UInt64
    public var peerBundle: PublicKeyBundle?
    public var peerDhPublicKey: Data
    public var isFirstReceivingRatchet: Bool
    public var rootKey: Data
    public var sendingStep: ChainStepState
    public var receivingStep: ChainStepState?

    public init(
        isInitiator: Bool,
        createdAt: Date,
        nonceCounter: UInt64,
        peerBundle: PublicKeyBundle?,
        peerDhPublicKey: Data,
        isFirstReceivingRatchet: Bool,
        rootKey: Data,
        sendingStep: ChainStepState,
        receivingStep: ChainStepState?
    ) {
        self.isInitiator = isInitiator
        self.createdAt = createdAt
        self.nonceCounter = nonceCounter
        self.peerBundle = peerBundle
        self.peerDhPublicKey = peerDhPublicKey
        self.isFirstReceivingRatchet = isFirstReceivingRatchet
        self.rootKey = rootKey
        self.sendingStep = sendingStep
        self.receivingStep = receivingStep
    }
}

// MARK: - Chain Step State
/// Corresponds to ChainStepState in protocol_state.proto
public struct ChainStepState: Codable {
    public var currentIndex: UInt32
    public var chainKey: Data
    public var dhPrivateKey: Data
    public var dhPublicKey: Data
    public var cachedMessageKeys: [CachedMessageKey]

    public init(
        currentIndex: UInt32,
        chainKey: Data,
        dhPrivateKey: Data,
        dhPublicKey: Data,
        cachedMessageKeys: [CachedMessageKey] = []
    ) {
        self.currentIndex = currentIndex
        self.chainKey = chainKey
        self.dhPrivateKey = dhPrivateKey
        self.dhPublicKey = dhPublicKey
        self.cachedMessageKeys = cachedMessageKeys
    }
}

// MARK: - Cached Message Key
/// Corresponds to CachedMessageKey in protocol_state.proto
public struct CachedMessageKey: Codable {
    public var index: UInt32
    public var keyMaterial: Data

    public init(index: UInt32, keyMaterial: Data) {
        self.index = index
        self.keyMaterial = keyMaterial
    }
}

// MARK: - Identity Keys State
/// Corresponds to IdentityKeysState in protocol_state.proto
public struct IdentityKeysState: Codable {
    public var ed25519SecretKey: Data
    public var identityX25519SecretKey: Data
    public var signedPreKeySecret: Data
    public var oneTimePreKeys: [OneTimePreKeySecret]

    public var ed25519PublicKey: Data
    public var identityX25519PublicKey: Data
    public var signedPreKeyId: UInt32
    public var signedPreKeyPublic: Data
    public var signedPreKeySignature: Data

    public init(
        ed25519SecretKey: Data,
        identityX25519SecretKey: Data,
        signedPreKeySecret: Data,
        oneTimePreKeys: [OneTimePreKeySecret],
        ed25519PublicKey: Data,
        identityX25519PublicKey: Data,
        signedPreKeyId: UInt32,
        signedPreKeyPublic: Data,
        signedPreKeySignature: Data
    ) {
        self.ed25519SecretKey = ed25519SecretKey
        self.identityX25519SecretKey = identityX25519SecretKey
        self.signedPreKeySecret = signedPreKeySecret
        self.oneTimePreKeys = oneTimePreKeys
        self.ed25519PublicKey = ed25519PublicKey
        self.identityX25519PublicKey = identityX25519PublicKey
        self.signedPreKeyId = signedPreKeyId
        self.signedPreKeyPublic = signedPreKeyPublic
        self.signedPreKeySignature = signedPreKeySignature
    }
}

// MARK: - One Time Pre Key Secret
/// Corresponds to OneTimePreKeySecret in protocol_state.proto
public struct OneTimePreKeySecret: Codable {
    public var preKeyId: UInt32
    public var privateKey: Data
    public var publicKey: Data

    public init(preKeyId: UInt32, privateKey: Data, publicKey: Data) {
        self.preKeyId = preKeyId
        self.privateKey = privateKey
        self.publicKey = publicKey
    }
}

// MARK: - Public Key Bundle
/// Corresponds to PublicKeyBundle in key_exchange.proto
public struct PublicKeyBundle: Codable {
    public var ed25519PublicKey: Data
    public var identityX25519: Data
    public var signedPreKeyId: UInt32
    public var signedPreKeyPublic: Data
    public var signedPreKeySignature: Data
    public var oneTimePreKeys: [OneTimePreKeyRecord]
    public var ephemeralX25519: Data?

    public init(
        ed25519PublicKey: Data,
        identityX25519: Data,
        signedPreKeyId: UInt32,
        signedPreKeyPublic: Data,
        signedPreKeySignature: Data,
        oneTimePreKeys: [OneTimePreKeyRecord],
        ephemeralX25519: Data?
    ) {
        self.ed25519PublicKey = ed25519PublicKey
        self.identityX25519 = identityX25519
        self.signedPreKeyId = signedPreKeyId
        self.signedPreKeyPublic = signedPreKeyPublic
        self.signedPreKeySignature = signedPreKeySignature
        self.oneTimePreKeys = oneTimePreKeys
        self.ephemeralX25519 = ephemeralX25519
    }
}

// MARK: - One Time Pre Key Record
/// Public record of a one-time pre-key
public struct OneTimePreKeyRecord: Codable {
    public var preKeyId: UInt32
    public var publicKey: Data

    public init(preKeyId: UInt32, publicKey: Data) {
        self.preKeyId = preKeyId
        self.publicKey = publicKey
    }
}

// MARK: - Protocol Failure Types
/// Failure types for protocol operations
public enum ProtocolFailure: LocalizedError {
    case encode(String)
    case decode(String)
    case bufferTooSmall(String)
    case generic(String)
    case prepareLocal(String)

    public var errorDescription: String? {
        switch self {
        case .encode(let message):
            return "Encoding failed: \(message)"
        case .decode(let message):
            return "Decoding failed: \(message)"
        case .bufferTooSmall(let message):
            return "Buffer too small: \(message)"
        case .generic(let message):
            return "Protocol error: \(message)"
        case .prepareLocal(let message):
            return "Local preparation failed: \(message)"
        }
    }
}
