import Combine
import EcliptixCore
import Foundation
import Observation

@MainActor
@Observable
public final class SignInService {

    public var mobileNumber: String = "" {
        didSet {
            if !hasMobileNumberBeenTouched && !mobileNumber.isEmpty {
                hasMobileNumberBeenTouched = true
            }
            validateMobileNumber()
        }
    }

    public var secureKey: String = "" {
        didSet {
            if !hasSecureKeyBeenTouched && !secureKey.isEmpty {
                hasSecureKeyBeenTouched = true
            }
            validateSecureKey()
        }
    }

    public var isBusy: Bool = false

    public var mobileNumberError: String?

    public var secureKeyError: String?

    public var serverError: String?

    private var hasMobileNumberBeenTouched: Bool = false

    private var hasSecureKeyBeenTouched: Bool = false

    private let authenticationService: AuthenticationService
    private let localization: LocalizationService
    private let mobileNumberValidator: MobileNumberValidator
    private let secureKeyValidator: SecureKeyValidator

    private var signInTask: Task<Void, Never>?

    public init(
        authenticationService: AuthenticationService,
        localization: LocalizationService
    ) {
        self.authenticationService = authenticationService
        self.localization = localization

        self.mobileNumberValidator = MobileNumberValidator(
            localization: localization,
            allowInternational: true
        )

        self.secureKeyValidator = SecureKeyValidator(
            localization: localization,
            minLength: 12,
            maxLength: 64
        )

        Log.debug("[SignInService] Initialized")
    }

    private func validateMobileNumber() {
        guard hasMobileNumberBeenTouched else {
            mobileNumberError = nil
            return
        }

        let validationResult = mobileNumberValidator.validate(mobileNumber)
        mobileNumberError = validationResult.errorMessage
    }

    private func validateSecureKey() {
        guard hasSecureKeyBeenTouched else {
            secureKeyError = nil
            return
        }

        let validationResult = secureKeyValidator.validate(secureKey)
        secureKeyError = validationResult.errorMessage
    }

    public func validateAll() {
        hasMobileNumberBeenTouched = true
        hasSecureKeyBeenTouched = true
        validateMobileNumber()
        validateSecureKey()
    }

    public func signIn() async -> Result<String, Error> {
        Log.info("[SignInService] Starting sign-in operation")

        cancelSignIn()

        validateAll()

        guard isFormValid else {
            let error = SignInError.validationFailed("Form validation failed")
            Log.warning("[SignInService] \(error.localizedDescription)")
            return .failure(error)
        }

        isBusy = true
        serverError = nil
        defer { isBusy = false }

        authenticationService.mobileNumber = mobileNumber
        authenticationService.secureKey = secureKey

        await authenticationService.signIn()

        let result: Result<String, Error>
        if let error = authenticationService.errorMessage {
            result = .failure(AuthenticationError.unknown(error))
        } else if case .complete(let userId) = authenticationService.currentStep {
            result = .success(userId)
        } else {
            result = .failure(AuthenticationError.unknown("Sign-in incomplete"))
        }

        switch result {
        case .success(let userId):
            Log.info("[SignInService] Sign-in successful for user: \(userId)")
            serverError = nil
            return .success(userId)

        case .failure(let error):
            let errorMessage = error.localizedDescription
            serverError = errorMessage
            hasSecureKeyBeenTouched = true
            Log.error("[SignInService] Sign-in failed: \(errorMessage)")
            return .failure(error)
        }
    }

    public func startAccountRecovery() {
        Log.info("[SignInService] Starting account recovery flow")
    }

    public func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        Log.debug("[SignInService] Sign-in operation cancelled")
    }

    public func reset() {
        Log.info("[SignInService] Resetting state")

        cancelSignIn()

        mobileNumber = ""
        secureKey = ""
        hasMobileNumberBeenTouched = false
        hasSecureKeyBeenTouched = false
        mobileNumberError = nil
        secureKeyError = nil
        serverError = nil
        isBusy = false
    }

    public func markMobileNumberAsTouched() {
        guard !hasMobileNumberBeenTouched else { return }
        hasMobileNumberBeenTouched = true
        validateMobileNumber()
    }

    public func markSecureKeyAsTouched() {
        guard !hasSecureKeyBeenTouched else { return }
        hasSecureKeyBeenTouched = true
        validateSecureKey()
    }

    public var hasMobileNumberError: Bool {
        mobileNumberError != nil && !mobileNumberError!.isEmpty
    }

    public var hasSecureKeyError: Bool {
        secureKeyError != nil && !secureKeyError!.isEmpty
    }

    public var hasServerError: Bool {
        serverError != nil && !serverError!.isEmpty
    }

    public var isFormValid: Bool {
        let mobileValid = mobileNumberValidator.validate(mobileNumber).isValid
        let keyValid = secureKeyValidator.validate(secureKey).isValid
        return mobileValid && keyValid
    }

    public var canSignIn: Bool {
        !isBusy && isFormValid
    }

    public var signInButtonText: String {
        localization[LocalizationKeys.Authentication.SignIn.signInButton] ?? "Sign In"
    }

    public var forgotSecureKeyText: String {
        localization[LocalizationKeys.Authentication.SignIn.forgotSecureKey] ?? "Forgot your secure key?"
    }

    public var noAccountText: String {
        localization[LocalizationKeys.Authentication.SignIn.noAccount] ?? "Don't have an account?"
    }

    public var registerText: String {
        localization[LocalizationKeys.Authentication.SignIn.register] ?? "Register"
    }

    public var welcomeBackText: String {
        localization[LocalizationKeys.Authentication.SignIn.welcomeBack] ?? "Welcome Back"
    }

    public var signInSubtitleText: String {
        localization[LocalizationKeys.Authentication.SignIn.subtitle] ?? "Sign in to continue to Ecliptix"
    }

    public var mobileNumberLabelText: String {
        localization[LocalizationKeys.Authentication.SignIn.mobileNumberLabel] ?? "Mobile Number"
    }

    public var secureKeyLabelText: String {
        localization[LocalizationKeys.Authentication.SignIn.secureKeyLabel] ?? "Secure Key"
    }
}

public enum SignInError: LocalizedError {
    case validationFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return message
        case .cancelled:
            return "Sign-in operation was cancelled"
        }
    }
}

public extension LocalizationKeys.Authentication {

    enum SignIn {
        public static let signInButton = "authentication.signIn.button"
        public static let forgotSecureKey = "authentication.signIn.forgotSecureKey"
        public static let noAccount = "authentication.signIn.noAccount"
        public static let register = "authentication.signIn.register"
        public static let welcomeBack = "authentication.signIn.welcomeBack"
        public static let subtitle = "authentication.signIn.subtitle"
        public static let mobileNumberLabel = "authentication.signIn.mobileNumberLabel"
        public static let secureKeyLabel = "authentication.signIn.secureKeyLabel"
    }
}
