import Foundation

public enum EnvelopeResultCode: Int32, Codable {
    case success = 0

    case badRequest = 1
    case unauthorized = 2
    case forbidden = 3
    case notFound = 4
    case methodNotAllowed = 5
    case conflict = 6
    case rateLimited = 7
    case payloadTooLarge = 8

    case internalError = 10
    case serviceUnavailable = 11
    case gatewayTimeout = 12
    case insufficientStorage = 13

    case cryptoError = 20
    case invalidSignature = 21
    case expiredKey = 22
    case ratchetError = 23
    case decryptionFailed = 24

    case networkError = 30
    case connectionLost = 31
    case timeout = 32
}

public enum EnvelopeType: Int32, Codable {
    case request = 0
    case response = 1
    case notification = 2
    case heartbeat = 3
    case errorResponse = 4
}

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

    public func toData() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    public static func fromData(_ data: Data) throws -> EnvelopeMetadata {
        let decoder = JSONDecoder()
        return try decoder.decode(EnvelopeMetadata.self, from: data)
    }
}

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

    public func toData() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
}

public struct SecureEnvelope: Codable, Sendable {
    public var metaData: Data
    public var encryptedPayload: Data
    public var resultCode: Data
    public var authenticationTag: Data?
    public var timestamp: Date
    public var errorDetails: Data?
    public var headerNonce: Data
    public var dhPublicKey: Data?

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

    public func toData() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    public static func fromData(_ data: Data) throws -> SecureEnvelope {
        let decoder = JSONDecoder()
        return try decoder.decode(SecureEnvelope.self, from: data)
    }
}

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

public struct OneTimePreKeyRecord: Codable {
    public var preKeyId: UInt32
    public var publicKey: Data

    public init(preKeyId: UInt32, publicKey: Data) {
        self.preKeyId = preKeyId
        self.publicKey = publicKey
    }
}

public enum ProtocolFailure: LocalizedError, Sendable {
    case encode(String)
    case decode(String)
    case bufferTooSmall(String)
    case generic(String)
    case prepareLocal(String)
    case connectionNotFound(String)
    case noDoubleRatchet(String)

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
        case .connectionNotFound(let message):
            return "Connection not found: \(message)"
        case .noDoubleRatchet(let message):
            return "Double Ratchet not initialized: \(message)"
        }
    }

    public var message: String {
        return errorDescription ?? "Unknown protocol error"
    }
}
