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
