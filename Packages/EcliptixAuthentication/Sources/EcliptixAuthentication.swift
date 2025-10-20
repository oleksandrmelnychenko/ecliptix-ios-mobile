import Foundation
import Combine
import EcliptixCore
import EcliptixNetworking
import EcliptixSecurity

// MARK: - Authentication Module
/// Authentication module providing sign-in, registration, and password recovery flows

public struct EcliptixAuthentication {
    public static let version = "1.0.0"

    public init() {}
}

// MARK: - Authentication Service Protocol
public protocol AuthenticationService {
    /// Initiates user registration with OPAQUE protocol
    func initiateRegistration(mobileNumber: String) async throws -> RegistrationSession

    /// Completes user registration
    func completeRegistration(session: RegistrationSession, password: String, verificationCode: String) async throws -> AuthenticationResult

    /// Initiates sign-in with OPAQUE protocol
    func initiateSignIn(mobileNumber: String) async throws -> SignInSession

    /// Completes sign-in
    func completeSignIn(session: SignInSession, password: String) async throws -> AuthenticationResult

    /// Initiates password recovery
    func initiatePasswordRecovery(mobileNumber: String) async throws -> PasswordRecoverySession

    /// Completes password recovery
    func completePasswordRecovery(session: PasswordRecoverySession, newPassword: String, verificationCode: String) async throws

    /// Logs out the current user
    func logout() async throws

    /// Validates mobile number format and availability
    func validateMobileNumber(_ mobileNumber: String) async throws -> MobileNumberValidation
}

// MARK: - Session Types
public struct RegistrationSession {
    public let sessionId: String
    public let mobileNumber: String
    public let timestamp: Date

    public init(sessionId: String, mobileNumber: String, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.mobileNumber = mobileNumber
        self.timestamp = timestamp
    }
}

public struct SignInSession {
    public let sessionId: String
    public let mobileNumber: String
    public let timestamp: Date

    public init(sessionId: String, mobileNumber: String, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.mobileNumber = mobileNumber
        self.timestamp = timestamp
    }
}

public struct PasswordRecoverySession {
    public let sessionId: String
    public let mobileNumber: String
    public let timestamp: Date

    public init(sessionId: String, mobileNumber: String, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.mobileNumber = mobileNumber
        self.timestamp = timestamp
    }
}

// MARK: - Authentication Result
public struct AuthenticationResult {
    public let userId: String
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date

    public init(userId: String, accessToken: String, refreshToken: String? = nil, expiresAt: Date) {
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

// MARK: - Mobile Number Validation
public struct MobileNumberValidation {
    public let isValid: Bool
    public let isAvailable: Bool
    public let formattedNumber: String?
    public let errorMessage: String?

    public init(isValid: Bool, isAvailable: Bool, formattedNumber: String? = nil, errorMessage: String? = nil) {
        self.isValid = isValid
        self.isAvailable = isAvailable
        self.formattedNumber = formattedNumber
        self.errorMessage = errorMessage
    }
}

// MARK: - Verification Service Protocol
public protocol VerificationService {
    /// Initiates OTP verification
    func initiateVerification(for mobileNumber: String, type: VerificationType) async throws -> String

    /// Verifies OTP code
    func verifyCode(_ code: String, verificationId: String) async throws -> Bool

    /// Resends verification code
    func resendCode(verificationId: String) async throws
}

public enum VerificationType {
    case registration
    case passwordRecovery
    case mobileVerification
}

// MARK: - Authentication Errors
public enum AuthenticationError: LocalizedError {
    case invalidCredentials
    case userNotFound
    case userAlreadyExists
    case invalidMobileNumber
    case invalidVerificationCode
    case sessionExpired
    case registrationFailed(String)
    case signInFailed(String)
    case passwordRecoveryFailed(String)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials provided"
        case .userNotFound:
            return "User not found"
        case .userAlreadyExists:
            return "User already exists"
        case .invalidMobileNumber:
            return "Invalid mobile number format"
        case .invalidVerificationCode:
            return "Invalid verification code"
        case .sessionExpired:
            return "Session has expired"
        case .registrationFailed(let message):
            return "Registration failed: \(message)"
        case .signInFailed(let message):
            return "Sign-in failed: \(message)"
        case .passwordRecoveryFailed(let message):
            return "Password recovery failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Authentication State Manager
@MainActor
public class AuthenticationStateManager: ObservableObject {
    @Published public private(set) var authenticationState: ApplicationState = .initializing
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: AuthenticationError?

    public init() {}

    public func updateState(_ state: ApplicationState) {
        self.authenticationState = state
    }

    public func setLoading(_ loading: Bool) {
        self.isLoading = loading
    }

    public func setError(_ error: AuthenticationError?) {
        self.error = error
    }
}
