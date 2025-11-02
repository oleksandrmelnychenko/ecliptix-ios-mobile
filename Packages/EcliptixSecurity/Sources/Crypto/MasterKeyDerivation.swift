import Crypto
import EcliptixCore
import Foundation

public final class MasterKeyDerivationService {

    private let argon2Service: Argon2idService

    public static let defaultKeySize = 32

    private static let identityKeyContext = "ecliptix-identity-key-v1"

    private static let recoveryKeyContext = "ecliptix-recovery-key-v1"

    public init(argon2Service: Argon2idService = Argon2idService()) {
        self.argon2Service = argon2Service
    }

    public func deriveMasterKey(
        password: String,
        salt: Data,
        preset: Argon2idService.Preset = .moderate,
        keyLength: Int = defaultKeySize
    ) throws -> Data {
        do {
            let masterKey = try argon2Service.deriveKey(
                password: password,
                salt: salt,
                keyLength: keyLength,
                preset: preset
            )

            Log.info("[MasterKeyDerivation] [OK] Derived \(keyLength)-byte master key using \(preset) preset")
            return masterKey

        } catch {
            Log.error("[MasterKeyDerivation] Failed to derive master key: \(error.localizedDescription)")
            throw MasterKeyError.derivationFailed(error.localizedDescription)
        }
    }

    public func deriveIdentityKey(
        from masterKey: Data,
        userId: UUID,
        keyLength: Int = defaultKeySize
    ) throws -> Data {

        var userIdBytes = userId.uuid
        let userIdData = withUnsafeBytes(of: &userIdBytes) { Data($0) }

        let info = Data(Self.identityKeyContext.utf8) + userIdData

        do {
            let identityKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: masterKey,
                salt: nil,
                info: info,
                outputByteCount: keyLength
            )

            Log.info("[MasterKeyDerivation] [OK] Derived identity key for user \(userId)")
            return identityKey

        } catch {
            Log.error("[MasterKeyDerivation] Failed to derive identity key: \(error.localizedDescription)")
            throw MasterKeyError.derivationFailed("Identity key derivation failed: \(error.localizedDescription)")
        }
    }

    public func deriveRecoveryKey(
        passphrase: String,
        salt: Data,
        preset: Argon2idService.Preset = .sensitive,
        keyLength: Int = defaultKeySize
    ) throws -> Data {
        do {

            let recoveryKey = try argon2Service.deriveKey(
                password: passphrase,
                salt: salt,
                keyLength: keyLength,
                preset: preset
            )

            Log.info("[MasterKeyDerivation] [OK] Derived \(keyLength)-byte recovery key using \(preset) preset")
            return recoveryKey

        } catch {
            Log.error("[MasterKeyDerivation] Failed to derive recovery key: \(error.localizedDescription)")
            throw MasterKeyError.derivationFailed(error.localizedDescription)
        }
    }

    public func deriveRecoverySubKey(
        from recoveryMasterKey: Data,
        context: String,
        keyLength: Int = defaultKeySize
    ) throws -> Data {
        let info = Data(Self.recoveryKeyContext.utf8) + Data(context.utf8)

        do {
            let subKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: recoveryMasterKey,
                salt: nil,
                info: info,
                outputByteCount: keyLength
            )

            Log.info("[MasterKeyDerivation] [OK] Derived recovery sub-key for context: \(context)")
            return subKey

        } catch {
            Log.error("[MasterKeyDerivation] Failed to derive recovery sub-key: \(error.localizedDescription)")
            throw MasterKeyError.derivationFailed("Recovery sub-key derivation failed: \(error.localizedDescription)")
        }
    }

    public func deriveCombinedKey(
        password: String,
        passwordSalt: Data,
        passphrase: String,
        passphraseSalt: Data,
        preset: Argon2idService.Preset = .moderate,
        keyLength: Int = defaultKeySize
    ) throws -> Data {
        do {

            let passwordKey = try argon2Service.deriveKey(
                password: password,
                salt: passwordSalt,
                keyLength: keyLength,
                preset: preset
            )

            let passphraseKey = try argon2Service.deriveKey(
                password: passphrase,
                salt: passphraseSalt,
                keyLength: keyLength,
                preset: preset
            )

            let combinedInput = passwordKey + passphraseKey
            let combinedKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: combinedInput,
                salt: Data("ecliptix-combined-key".utf8),
                info: Data("v1".utf8),
                outputByteCount: keyLength
            )

            Log.info("[MasterKeyDerivation] [OK] Derived combined key from password + passphrase")

            var passwordKeyCopy = passwordKey
            var passphraseKeyCopy = passphraseKey
            CryptographicHelpers.secureWipe(&passwordKeyCopy)
            CryptographicHelpers.secureWipe(&passphraseKeyCopy)

            return combinedKey

        } catch {
            Log.error("[MasterKeyDerivation] Failed to derive combined key: \(error.localizedDescription)")
            throw MasterKeyError.derivationFailed(error.localizedDescription)
        }
    }

    public func generateSalt() -> Data {
        return argon2Service.generateSalt()
    }

    public func validatePasswordStrength(_ password: String) -> PasswordStrengthResult {
        let length = password.count
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecial = password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil

        guard length >= 12 else {
            return PasswordStrengthResult(
                strength: .weak,
                message: "Password must be at least 12 characters long for security.",
                score: 0
            )
        }

        guard hasUppercase && hasLowercase && hasDigit else {
            return PasswordStrengthResult(
                strength: .weak,
                message: "Password must contain uppercase, lowercase, and numbers.",
                score: 1
            )
        }

        var score = 0

        if length >= 12 { score += 1 }
        if length >= 16 { score += 1 }
        if length >= 20 { score += 1 }

        if hasUppercase { score += 1 }
        if hasLowercase { score += 1 }
        if hasDigit { score += 1 }
        if hasSpecial { score += 1 }

        let strength: PasswordStrength
        let message: String

        switch score {
        case 0...3:
            strength = .weak
            message = "Password meets minimum requirements but could be stronger."
        case 4...5:
            strength = .fair
            message = "Password strength is fair. Consider adding special characters or making it longer."
        case 6:
            strength = .good
            message = "Password strength is good."
        default:
            strength = .strong
            message = "Password strength is strong."
        }

        return PasswordStrengthResult(strength: strength, message: message, score: score)
    }
}

public enum MasterKeyError: LocalizedError {
    case derivationFailed(String)
    case invalidSalt
    case weakPassword

    public var errorDescription: String? {
        switch self {
        case .derivationFailed(let msg):
            return "Master key derivation failed: \(msg)"
        case .invalidSalt:
            return "Invalid salt (must be 16 bytes)"
        case .weakPassword:
            return "Password is too weak for secure key derivation"
        }
    }
}

public enum PasswordStrength {
    case weak
    case fair
    case good
    case strong
}

public struct PasswordStrengthResult {
    public let strength: PasswordStrength
    public let message: String
    public let score: Int

    public var isAcceptable: Bool {
        switch strength {
        case .weak:
            return false
        case .fair, .good, .strong:
            return true
        }
    }
}
