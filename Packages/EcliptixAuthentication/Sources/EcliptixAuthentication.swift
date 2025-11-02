import Combine
import EcliptixCore
import EcliptixNetworking
import EcliptixSecurity
import Foundation

public struct EcliptixAuthentication {
    public static let version = "1.0.0"

    public init() {}
}
public protocol AuthenticationService {

    func initiateRegistration(mobileNumber: String) async throws -> RegistrationSession

    func completeRegistration(session: RegistrationSession, password: String, verificationCode: String) async throws -> AuthenticationResult

    func initiateSignIn(mobileNumber: String) async throws -> SignInSession

    func completeSignIn(session: SignInSession, password: String) async throws -> AuthenticationResult

    func initiatePasswordRecovery(mobileNumber: String) async throws -> PasswordRecoverySession

    func completePasswordRecovery(session: PasswordRecoverySession, newPassword: String, verificationCode: String) async throws

    func logout() async throws

    func validateMobileNumber(_ mobileNumber: String) async throws -> MobileNumberValidation
}
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
public protocol VerificationService {

    func initiateVerification(for mobileNumber: String, type: VerificationType) async throws -> String

    func verifyCode(_ code: String, verificationId: String) async throws -> Bool

    func resendCode(verificationId: String) async throws
}

public enum VerificationType {
    case registration
    case passwordRecovery
    case mobileVerification
}
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
@MainActor
public class AuthenticationStateManager: ObservableObject {
    @Published public private(set) var authenticationState: ApplicationState = .initializing
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: AuthenticationError?

    public init() {}

    public func updateState(_ state: ApplicationState) {
        self.authenticationState = state
    }

    public func updateLoading(_ loading: Bool) {
        self.isLoading = loading
    }

    public func updateError(_ error: AuthenticationError?) {
        self.error = error
    }
}
