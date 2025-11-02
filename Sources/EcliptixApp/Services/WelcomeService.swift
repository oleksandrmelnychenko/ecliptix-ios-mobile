import Combine
import EcliptixCore
import Foundation
import Observation

public enum AuthenticationFlowContext: Equatable {
    case registration
    case secureKeyRecovery
}

@MainActor
@Observable
public final class WelcomeService {

    public var isCreateAccountBusy: Bool = false

    public var isSignInBusy: Bool = false

    public var currentFlowContext: AuthenticationFlowContext?

    private let localization: LocalizationService

    public init(localization: LocalizationService) {
        self.localization = localization
        Log.debug("[WelcomeService] Initialized")
    }

    public func navigateToCreateAccount() async -> AuthenticationFlowContext {
        Log.info("[WelcomeService] Navigating to Create Account")

        isCreateAccountBusy = true
        defer { isCreateAccountBusy = false }

        try? await Task.sleep(nanoseconds: 100_000_000)

        currentFlowContext = .registration
        Log.debug("[WelcomeService] Flow context set to: Registration")

        return .registration
    }

    public func navigateToSignIn() async -> AuthenticationFlowContext {
        Log.info("[WelcomeService] Navigating to Sign In")

        isSignInBusy = true
        defer { isSignInBusy = false }

        try? await Task.sleep(nanoseconds: 100_000_000)

        currentFlowContext = .secureKeyRecovery
        Log.debug("[WelcomeService] Flow context set to: Secure Key Recovery")

        return .secureKeyRecovery
    }

    public func reset() {
        Log.info("[WelcomeService] Resetting state")
        isCreateAccountBusy = false
        isSignInBusy = false
        currentFlowContext = nil
    }
}

public extension WelcomeService {

    var isBusy: Bool {
        isCreateAccountBusy || isSignInBusy
    }

    var canNavigate: Bool {
        !isBusy
    }

    var welcomeTitle: String {
        localization[LocalizationKeys.Authentication.Welcome.title] ?? "Welcome to Ecliptix"
    }

    var welcomeTagline: String {
        localization[LocalizationKeys.Authentication.Welcome.tagline] ?? "Secure messaging and authentication"
    }

    var signInButtonText: String {
        localization[LocalizationKeys.Authentication.Welcome.signIn] ?? "Sign In"
    }

    var createAccountButtonText: String {
        localization[LocalizationKeys.Authentication.Welcome.createAccount] ?? "Create Account"
    }
}

public extension LocalizationKeys.Authentication {

    enum Welcome {
        public static let title = "authentication.welcome.title"
        public static let tagline = "authentication.welcome.tagline"
        public static let signIn = "authentication.welcome.signIn"
        public static let createAccount = "authentication.welcome.createAccount"
    }
}
