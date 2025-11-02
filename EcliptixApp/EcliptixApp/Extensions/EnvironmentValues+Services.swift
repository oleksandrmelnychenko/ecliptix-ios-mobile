import SwiftUI

private struct AuthenticationServiceKey: EnvironmentKey {
    static let defaultValue: AuthenticationService? = nil
}

private struct RegistrationServiceKey: EnvironmentKey {
    static let defaultValue: RegistrationService? = nil
}

private struct PasswordRecoveryServiceKey: EnvironmentKey {
    static let defaultValue: PasswordRecoveryService? = nil
}

private struct LogoutServiceKey: EnvironmentKey {
    static let defaultValue: LogoutService? = nil
}

private struct ApplicationStateManagerKey: EnvironmentKey {
    static let defaultValue: ApplicationStateManager? = nil
}

private struct ApplicationRouterKey: EnvironmentKey {
    static let defaultValue: ApplicationRouter? = nil
}

private struct E2EEncryptionServiceKey: EnvironmentKey {
    static let defaultValue: E2EEncryptionService? = nil
}

private struct WelcomeServiceKey: EnvironmentKey {
    static let defaultValue: WelcomeService? = nil
}

private struct SignInServiceKey: EnvironmentKey {
    static let defaultValue: SignInService? = nil
}

public extension EnvironmentValues {
    var authenticationService: AuthenticationService {
        get { self[AuthenticationServiceKey.self] ?? createDefaultAuthService() }
        set { self[AuthenticationServiceKey.self] = newValue }
    }

    var registrationService: RegistrationService {
        get { self[RegistrationServiceKey.self] ?? createDefaultRegistrationService() }
        set { self[RegistrationServiceKey.self] = newValue }
    }

    var passwordRecoveryService: PasswordRecoveryService {
        get { self[PasswordRecoveryServiceKey.self] ?? createDefaultPasswordRecoveryService() }
        set { self[PasswordRecoveryServiceKey.self] = newValue }
    }

    var logoutService: LogoutService {
        get { self[LogoutServiceKey.self] ?? createDefaultLogoutService() }
        set { self[LogoutServiceKey.self] = newValue }
    }

    var applicationStateManager: ApplicationStateManager {
        get { self[ApplicationStateManagerKey.self] ?? createDefaultStateManager() }
        set { self[ApplicationStateManagerKey.self] = newValue }
    }

    var applicationRouter: ApplicationRouter {
        get { self[ApplicationRouterKey.self] ?? createDefaultRouter() }
        set { self[ApplicationRouterKey.self] = newValue }
    }

    var e2eEncryptionService: E2EEncryptionService {
        get { self[E2EEncryptionServiceKey.self] ?? createDefaultE2EEncryptionService() }
        set { self[E2EEncryptionServiceKey.self] = newValue }
    }

    var welcomeService: WelcomeService {
        get { self[WelcomeServiceKey.self] ?? createDefaultWelcomeService() }
        set { self[WelcomeServiceKey.self] = newValue }
    }

    var signInService: SignInService {
        get { self[SignInServiceKey.self] ?? createDefaultSignInService() }
        set { self[SignInServiceKey.self] = newValue }
    }

    private func createDefaultAuthService() -> AuthenticationService {
        fatalError("AuthenticationService not found in environment. Please inject it at the app root.")
    }

    private func createDefaultRegistrationService() -> RegistrationService {
        fatalError("RegistrationService not found in environment. Please inject it at the app root.")
    }

    private func createDefaultPasswordRecoveryService() -> PasswordRecoveryService {
        fatalError("PasswordRecoveryService not found in environment. Please inject it at the app root.")
    }

    private func createDefaultLogoutService() -> LogoutService {
        fatalError("LogoutService not found in environment. Please inject it at the app root.")
    }

    private func createDefaultE2EEncryptionService() -> E2EEncryptionService {
        fatalError("E2EEncryptionService not found in environment. Please inject it at the app root.")
    }

    private func createDefaultStateManager() -> ApplicationStateManager {
        fatalError("ApplicationStateManager not found in environment. Please inject it at the app root.")
    }

    private func createDefaultRouter() -> ApplicationRouter {
        fatalError("ApplicationRouter not found in environment. Please inject it at the app root.")
    }

    private func createDefaultWelcomeService() -> WelcomeService {
        fatalError("WelcomeService not found in environment. Please inject it at the app root.")
    }

    private func createDefaultSignInService() -> SignInService {
        fatalError("SignInService not found in environment. Please inject it at the app root.")
    }
}

public extension View {

    func authenticationService(_ service: AuthenticationService) -> some View {
        environment(\.authenticationService, service)
    }

    func registrationService(_ service: RegistrationService) -> some View {
        environment(\.registrationService, service)
    }

    func passwordRecoveryService(_ service: PasswordRecoveryService) -> some View {
        environment(\.passwordRecoveryService, service)
    }

    func logoutService(_ service: LogoutService) -> some View {
        environment(\.logoutService, service)
    }

    func applicationStateManager(_ service: ApplicationStateManager) -> some View {
        environment(\.applicationStateManager, service)
    }

    func applicationRouter(_ service: ApplicationRouter) -> some View {
        environment(\.applicationRouter, service)
    }

    func e2eEncryptionService(_ service: E2EEncryptionService) -> some View {
        environment(\.e2eEncryptionService, service)
    }

    func welcomeService(_ service: WelcomeService) -> some View {
        environment(\.welcomeService, service)
    }

    func signInService(_ service: SignInService) -> some View {
        environment(\.signInService, service)
    }

    func injectServices(
        authService: AuthenticationService,
        registrationService: RegistrationService,
        passwordRecoveryService: PasswordRecoveryService,
        logoutService: LogoutService,
        stateManager: ApplicationStateManager,
        router: ApplicationRouter,
        e2eEncryption: E2EEncryptionService
    ) -> some View {
        self
            .authenticationService(authService)
            .registrationService(registrationService)
            .passwordRecoveryService(passwordRecoveryService)
            .logoutService(logoutService)
            .applicationStateManager(stateManager)
            .applicationRouter(router)
            .e2eEncryptionService(e2eEncryption)
    }
}
