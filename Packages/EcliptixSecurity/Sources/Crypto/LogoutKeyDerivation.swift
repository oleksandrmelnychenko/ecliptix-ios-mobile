import Crypto
import EcliptixCore
import Foundation

public final class LogoutKeyDerivationService {

    private let masterKeyDerivation: MasterKeyDerivationService

    private static let logoutKeyContext = "ecliptix-logout-key-v1"

    private static let sessionTerminationContext = "ecliptix-session-termination-v1"

    private static let wipeVerificationContext = "ecliptix-wipe-verification-v1"

    public static let defaultKeySize = 32

    public init(masterKeyDerivation: MasterKeyDerivationService = MasterKeyDerivationService()) {
        self.masterKeyDerivation = masterKeyDerivation
    }

    public func deriveLogoutKey(
        from masterKey: Data,
        membershipId: UUID,
        sessionId: String? = nil,
        keyLength: Int = defaultKeySize
    ) throws -> Data {

        var uuidBytes = membershipId.uuid
        let membershipIdData = withUnsafeBytes(of: &uuidBytes) { Data($0) }

        var info = Data(Self.logoutKeyContext.utf8) + membershipIdData

        if let sessionId = sessionId, let sessionData = sessionId.data(using: .utf8) {
            info += sessionData
        }

        do {
            let logoutKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: masterKey,
                salt: Data("ecliptix-logout-salt".utf8),
                info: info,
                outputByteCount: keyLength
            )

            Log.info("[LogoutKeyDerivation] [OK] Derived logout key for membership: \(membershipId)")
            return logoutKey

        } catch {
            Log.error("[LogoutKeyDerivation] Failed to derive logout key: \(error.localizedDescription)")
            throw LogoutKeyError.derivationFailed("Logout key derivation failed: \(error.localizedDescription)")
        }
    }

    public func deriveSessionTerminationKey(
        from logoutKey: Data,
        timestamp: Date = Date(),
        keyLength: Int = defaultKeySize
    ) throws -> Data {

        let timestampSeconds = UInt64(timestamp.timeIntervalSince1970)
        var timestampData = Data()
        withUnsafeBytes(of: timestampSeconds.bigEndian) { bytes in
            timestampData.append(contentsOf: bytes)
        }

        let info = Data(Self.sessionTerminationContext.utf8) + timestampData

        do {
            let terminationKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: logoutKey,
                salt: Data("ecliptix-termination-salt".utf8),
                info: info,
                outputByteCount: keyLength
            )

            Log.info("[LogoutKeyDerivation] [OK] Derived session termination key")
            return terminationKey

        } catch {
            Log.error("[LogoutKeyDerivation] Failed to derive termination key: \(error.localizedDescription)")
            throw LogoutKeyError.derivationFailed("Termination key derivation failed: \(error.localizedDescription)")
        }
    }

    public func deriveWipeVerificationKey(
        from logoutKey: Data,
        keyLength: Int = defaultKeySize
    ) throws -> Data {
        let info = Data(Self.wipeVerificationContext.utf8)

        do {
            let verificationKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: logoutKey,
                salt: Data("ecliptix-wipe-verification-salt".utf8),
                info: info,
                outputByteCount: keyLength
            )

            Log.debug("[LogoutKeyDerivation] Derived wipe verification key")
            return verificationKey

        } catch {
            Log.error("[LogoutKeyDerivation] Failed to derive verification key: \(error.localizedDescription)")
            throw LogoutKeyError.derivationFailed("Verification key derivation failed: \(error.localizedDescription)")
        }
    }

    public func deriveLogoutKeyBundle(
        from masterKey: Data,
        membershipId: UUID,
        sessionId: String? = nil
    ) throws -> LogoutKeyBundle {

        let logoutKey = try deriveLogoutKey(
            from: masterKey,
            membershipId: membershipId,
            sessionId: sessionId
        )

        let terminationKey = try deriveSessionTerminationKey(from: logoutKey)

        let verificationKey = try deriveWipeVerificationKey(from: logoutKey)

        Log.info("[LogoutKeyDerivation] [OK] Derived complete logout key bundle")

        return LogoutKeyBundle(
            logoutKey: logoutKey,
            terminationKey: terminationKey,
            verificationKey: verificationKey,
            membershipId: membershipId,
            sessionId: sessionId,
            createdAt: Date()
        )
    }

    public func secureWipeBundle(_ bundle: inout LogoutKeyBundle) {

        CryptographicHelpers.secureWipe(&bundle.logoutKey)
        CryptographicHelpers.secureWipe(&bundle.terminationKey)
        CryptographicHelpers.secureWipe(&bundle.verificationKey)

        Log.info("[LogoutKeyDerivation] [OK] Securely wiped logout key bundle")
    }

    public func verifyKeyWiped(_ key: Data) -> Bool {
        let isWiped = key.allSatisfy { $0 == 0 }

        if isWiped {
            Log.debug("[LogoutKeyDerivation] [OK] Key wipe verified")
        } else {
            Log.warning("[LogoutKeyDerivation] [WARNING] Key may not be fully wiped")
        }

        return isWiped
    }

    public func generateLogoutToken(
        using logoutKey: Data,
        membershipId: UUID,
        timestamp: Date = Date()
    ) throws -> Data {

        var uuidBytes = membershipId.uuid
        let membershipIdData = withUnsafeBytes(of: &uuidBytes) { Data($0) }

        let timestampSeconds = UInt64(timestamp.timeIntervalSince1970)
        var timestampData = Data()
        withUnsafeBytes(of: timestampSeconds.bigEndian) { bytes in
            timestampData.append(contentsOf: bytes)
        }

        let payload = Data("LOGOUT".utf8) + membershipIdData + timestampData

        let key = SymmetricKey(data: logoutKey)
        let signature = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        let signatureData = Data(signature)

        let token = payload + signatureData

        Log.info("[LogoutKeyDerivation] [OK] Generated signed logout token")
        return token
    }

    public func verifyLogoutToken(
        _ token: Data,
        using logoutKey: Data
    ) -> Bool {

        let signatureSize = 32
        guard token.count > signatureSize else {
            Log.warning("[LogoutKeyDerivation] Invalid token: too short")
            return false
        }

        let payload = token.dropLast(signatureSize)
        let providedSignature = token.suffix(signatureSize)

        let key = SymmetricKey(data: logoutKey)
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        let expectedSignatureData = Data(expectedSignature)

        let isValid = CryptographicHelpers.constantTimeEquals(providedSignature, expectedSignatureData)

        if isValid {
            Log.info("[LogoutKeyDerivation] [OK] Logout token verified")
        } else {
            Log.warning("[LogoutKeyDerivation] [WARNING] Invalid logout token signature")
        }

        return isValid
    }
}

public enum LogoutKeyError: LocalizedError {
    case derivationFailed(String)
    case invalidKey
    case tokenGenerationFailed
    case tokenVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .derivationFailed(let msg):
            return "Logout key derivation failed: \(msg)"
        case .invalidKey:
            return "Invalid logout key"
        case .tokenGenerationFailed:
            return "Failed to generate logout token"
        case .tokenVerificationFailed:
            return "Failed to verify logout token"
        }
    }
}

public struct LogoutKeyBundle {

    public var logoutKey: Data

    public var terminationKey: Data

    public var verificationKey: Data

    public let membershipId: UUID

    public let sessionId: String?

    public let createdAt: Date

    public var expiresAt: Date {
        return createdAt.addingTimeInterval(3600)
    }

    public var isExpired: Bool {
        return Date() > expiresAt
    }

    public init(
        logoutKey: Data,
        terminationKey: Data,
        verificationKey: Data,
        membershipId: UUID,
        sessionId: String?,
        createdAt: Date
    ) {
        self.logoutKey = logoutKey
        self.terminationKey = terminationKey
        self.verificationKey = verificationKey
        self.membershipId = membershipId
        self.sessionId = sessionId
        self.createdAt = createdAt
    }
}
