import Clibsodium
import EcliptixCore
import Foundation

public final class Argon2idService {

    public enum Preset {

        case interactive

        case moderate

        case sensitive

        var opsLimit: UInt64 {
            switch self {
            case .interactive:
                return UInt64(crypto_pwhash_argon2id_OPSLIMIT_INTERACTIVE)
            case .moderate:
                return UInt64(crypto_pwhash_argon2id_OPSLIMIT_MODERATE)
            case .sensitive:
                return UInt64(crypto_pwhash_argon2id_OPSLIMIT_SENSITIVE)
            }
        }

        var memLimit: Int {
            switch self {
            case .interactive:
                return Int(crypto_pwhash_argon2id_MEMLIMIT_INTERACTIVE)
            case .moderate:
                return Int(crypto_pwhash_argon2id_MEMLIMIT_MODERATE)
            case .sensitive:
                return Int(crypto_pwhash_argon2id_MEMLIMIT_SENSITIVE)
            }
        }
    }

    private static let algorithm = crypto_pwhash_argon2id_ALG_ARGON2ID13

    public static let saltSize = crypto_pwhash_argon2id_SALTBYTES

    public static let minKeySize = Int(crypto_pwhash_argon2id_BYTES_MIN)

    public static let maxKeySize = Int.max

    public init() {
        let initResult = sodium_init()
        if initResult == -1 {
            Log.error("[Argon2id] Failed to initialize libsodium")
        }
    }

    public func deriveKey(
        password: String,
        salt: Data,
        keyLength: Int = 32,
        preset: Preset = .moderate
    ) throws -> Data {
        guard let passwordData = password.data(using: .utf8) else {
            throw Argon2Error.invalidPassword
        }

        return try deriveKey(
            passwordData: passwordData,
            salt: salt,
            keyLength: keyLength,
            preset: preset
        )
    }

    public func deriveKey(
        passwordData: Data,
        salt: Data,
        keyLength: Int = 32,
        preset: Preset = .moderate
    ) throws -> Data {
        guard salt.count == Self.saltSize else {
            throw Argon2Error.invalidSalt("Salt must be \(Self.saltSize) bytes, got \(salt.count)")
        }

        guard keyLength >= Self.minKeySize && keyLength <= Self.maxKeySize else {
            throw Argon2Error.invalidKeyLength("Key length must be between \(Self.minKeySize) and \(Self.maxKeySize), got \(keyLength)")
        }

        var output = Data(count: keyLength)

        let result = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    guard let outPtr = outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let pwdPtr = passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                          let saltPtr = saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return Int32(-1)
                    }
                    return crypto_pwhash_argon2id(
                        outPtr,
                        UInt64(keyLength),
                        pwdPtr,
                        UInt64(passwordData.count),
                        saltPtr,
                        preset.opsLimit,
                        preset.memLimit,
                        Int32(Self.algorithm)
                    )
                }
            }
        }

        guard result == 0 else {
            throw Argon2Error.derivationFailed("crypto_pwhash_argon2id returned \(result)")
        }

        Log.info("[Argon2id] Successfully derived \(keyLength)-byte key using \(preset) preset")
        return output
    }

    public func deriveKeyCustom(
        passwordData: Data,
        salt: Data,
        keyLength: Int,
        opsLimit: UInt64,
        memLimit: Int
    ) throws -> Data {
        guard salt.count == Self.saltSize else {
            throw Argon2Error.invalidSalt("Salt must be \(Self.saltSize) bytes")
        }

        guard keyLength >= Self.minKeySize && keyLength <= Self.maxKeySize else {
            throw Argon2Error.invalidKeyLength("Invalid key length")
        }

        var output = Data(count: keyLength)

        let result = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    guard let outPtr = outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let pwdPtr = passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                          let saltPtr = saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return Int32(-1)
                    }
                    return crypto_pwhash_argon2id(
                        outPtr,
                        UInt64(keyLength),
                        pwdPtr,
                        UInt64(passwordData.count),
                        saltPtr,
                        opsLimit,
                        memLimit,
                        Int32(Self.algorithm)
                    )
                }
            }
        }

        guard result == 0 else {
            throw Argon2Error.derivationFailed("crypto_pwhash_argon2id returned \(result)")
        }

        return output
    }

    public func hashPassword(
        _ password: String,
        preset: Preset = .moderate
    ) throws -> String {
        guard let passwordData = password.data(using: .utf8) else {
            throw Argon2Error.invalidPassword
        }

        var hashBuffer = [Int8](repeating: 0, count: Int(crypto_pwhash_argon2id_STRBYTES))

        let result = passwordData.withUnsafeBytes { passwordBytes in
            guard let passwordPtr = passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self) else {
                return Int32(-1)
            }
            return crypto_pwhash_argon2id_str(
                &hashBuffer,
                passwordPtr,
                UInt64(passwordData.count),
                preset.opsLimit,
                preset.memLimit
            )
        }

        guard result == 0 else {
            throw Argon2Error.hashingFailed("crypto_pwhash_argon2id_str returned \(result)")
        }

        guard let hashString = String(cString: hashBuffer, encoding: .utf8) else {
            throw Argon2Error.hashingFailed("Failed to convert hash to string")
        }

        return hashString
    }

    public func verifyPassword(
        _ password: String,
        against hashString: String
    ) throws -> Bool {
        guard let passwordData = password.data(using: .utf8) else {
            throw Argon2Error.invalidPassword
        }

        guard let hashCString = hashString.cString(using: .utf8) else {
            throw Argon2Error.invalidHash
        }

        let result = passwordData.withUnsafeBytes { passwordBytes in
            guard let passwordPtr = passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self) else {
                return Int32(-1)
            }
            return hashCString.withUnsafeBufferPointer { hashPtr in
                guard let hashBasePtr = hashPtr.baseAddress else {
                    return Int32(-1)
                }
                return crypto_pwhash_argon2id_str_verify(
                    hashBasePtr,
                    passwordPtr,
                    UInt64(passwordData.count)
                )
            }
        }

        return result == 0
    }

    public func generateSalt() -> Data {
        let saltSizeInt = Int(Self.saltSize)
        var salt = Data(count: saltSizeInt)
        salt.withUnsafeMutableBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            randombytes_buf(ptr, saltSizeInt)
        }
        return salt
    }
}
public enum Argon2Error: LocalizedError {
    case invalidPassword
    case invalidSalt(String)
    case invalidKeyLength(String)
    case invalidHash
    case derivationFailed(String)
    case hashingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return "Invalid password (not UTF-8 encodable)"
        case .invalidSalt(let msg):
            return "Invalid salt: \(msg)"
        case .invalidKeyLength(let msg):
            return "Invalid key length: \(msg)"
        case .invalidHash:
            return "Invalid hash string"
        case .derivationFailed(let msg):
            return "Argon2id derivation failed: \(msg)"
        case .hashingFailed(let msg):
            return "Argon2id hashing failed: \(msg)"
        }
    }
}
