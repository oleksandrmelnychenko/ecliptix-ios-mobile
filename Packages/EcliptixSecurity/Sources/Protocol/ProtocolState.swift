import EcliptixCore
import EcliptixProto
import Foundation

public typealias RatchetState = Protocol_RatchetState
public typealias ChainStepState = Protocol_ChainStepState
public typealias PublicKeyBundle = Protocol_PublicKeyBundle
public typealias CachedMessageKey = Protocol_CachedMessageKey

public struct ProtocolSessionState {
    public let connectId: UInt32
    public let identityKeysState: IdentityKeysState
    public let ratchetState: RatchetState?
    public let createdAt: Date

    public init(
        connectId: UInt32,
        identityKeysState: IdentityKeysState,
        ratchetState: RatchetState?,
        createdAt: Date
    ) {
        self.connectId = connectId
        self.identityKeysState = identityKeysState
        self.ratchetState = ratchetState
        self.createdAt = createdAt
    }
}

extension ProtocolSessionState: Codable {
    enum CodingKeys: String, CodingKey {
        case connectId
        case identityKeysState
        case ratchetStateData
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connectId = try container.decode(UInt32.self, forKey: .connectId)
        identityKeysState = try container.decode(IdentityKeysState.self, forKey: .identityKeysState)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        if let ratchetData = try container.decodeIfPresent(Data.self, forKey: .ratchetStateData) {
            ratchetState = try Protocol_RatchetState(serializedBytes: ratchetData)
        } else {
            ratchetState = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(connectId, forKey: .connectId)
        try container.encode(identityKeysState, forKey: .identityKeysState)
        try container.encode(createdAt, forKey: .createdAt)

        if let ratchetState = ratchetState {
            let ratchetData = try ratchetState.serializedData()
            try container.encode(ratchetData, forKey: .ratchetStateData)
        }
    }
}

public struct IdentityKeysState: Codable {
    public let ed25519SecretKey: Data
    public let identityX25519SecretKey: Data
    public let signedPreKeySecret: Data
    public let oneTimePreKeys: [OneTimePreKeySecret]
    public let ed25519PublicKey: Data
    public let identityX25519PublicKey: Data
    public let signedPreKeyId: UInt32
    public let signedPreKeyPublic: Data
    public let signedPreKeySignature: Data

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
    public let preKeyId: UInt32
    public let privateKey: Data
    public let publicKey: Data

    public init(preKeyId: UInt32, privateKey: Data, publicKey: Data) {
        self.preKeyId = preKeyId
        self.privateKey = privateKey
        self.publicKey = publicKey
    }
}
