import Foundation

public struct CryptographicConstants {
    public static let x25519KeySize = 32
    public static let ed25519KeySize = 32
    public static let ed25519PublicKeySize = 32
    public static let ed25519SecretKeySize = 64
    public static let ed25519SignatureSize = 64
    public static let x25519PublicKeySize = 32
    public static let x25519PrivateKeySize = 32
    public static let aesKeySize = 32
    public static let aesGcmNonceSize = 12
    public static let aesGcmTagSize = 16
    public static let sha256HashSize = 32
    public static let blake2BSaltSize = 16
    public static let blake2BPersonalSize = 16
    public static let hashFingerprintLength = 16
    public static let guidByteLength = 16
    public static let aesIvSize = 16
    public static let curve25519FieldElementSize = 32
    public static let wordSize = 4
    public static let field256WordCount = 8
    public static let fieldElementMask: UInt32 = 0x7FFFFFFF
    public static let msgInfo: [UInt8] = [0x01]
    public static let chainInfo: [UInt8] = [0x02]
    public static let x3dhInfo = "ecliptix-x3dh-v1"
    public struct Argon2 {
        public static let defaultIterations = 4
        public static let defaultMemorySize = 262144
        public static let defaultParallelism = 4
        public static let defaultOutputLength = 64
    }
    public struct Buffer {
        public static let maxInfoSize = 128
        public static let maxPreviousBlockSize = 64
        public static let maxRoundSize = 64
    }
    public struct KeyDerivation {
        public static let additionalRoundsCount = 3
        public static let roundKeyFormat = "round-%d"
    }
    public struct RSA {
        public static let maxChunkSize = 120
        public static let encryptedChunkSize = 256
    }
}
