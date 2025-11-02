import EcliptixAuthentication
import EcliptixCore
import EcliptixNetworking
import EcliptixSecurity
import SwiftUI

@main
struct EcliptixApp: App {
    @StateObject private var serviceContainer = ServiceContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .injectServices(
                    authService: serviceContainer.authenticationService,
                    registrationService: serviceContainer.registrationService,
                    passwordRecoveryService: serviceContainer.passwordRecoveryService,
                    logoutService: serviceContainer.logoutService,
                    stateManager: serviceContainer.stateManager,
                    router: serviceContainer.router,
                    e2eEncryption: serviceContainer.e2eEncryptionService
                )
                .welcomeService(serviceContainer.welcomeService)
                .signInService(serviceContainer.signInService)
                .task {
                    await serviceContainer.initialize()
                }
        }
    }
}

@MainActor
final class ServiceContainer: ObservableObject {
    let connectivityService: ConnectivityService
    let localizationService: LocalizationService
    let identityService: IdentityService
    let secureStorage: ApplicationSecureStorageProvider
    let networkProvider: NetworkProvider
    let stateManager: ApplicationStateManager
    let router: ApplicationRouter
    let opaqueAuthService: OpaqueAuthenticationService
    let e2eEncryptionService: E2EEncryptionService

    @Published private(set) var hasIdentityKeys: Bool = false

    let authenticationService: AuthenticationService
    let registrationService: RegistrationService
    let passwordRecoveryService: PasswordRecoveryService
    let logoutService: LogoutService
    let welcomeService: WelcomeService
    let signInService: SignInService

    init() {
        self.connectivityService = DefaultConnectivityService()
        self.localizationService = DefaultLocalizationService()
        self.identityService = KeychainIdentityService()
        self.secureStorage = ApplicationSecureStorageProvider()

        self.networkProvider = NetworkProvider(
            connectivityService: connectivityService
        )

        self.stateManager = ApplicationStateManager()
        self.router = ApplicationRouter(stateManager: stateManager)

        let membershipClient = networkProvider.membershipClient
        let deviceClient = networkProvider.deviceClient
        self.opaqueAuthService = OpaqueAuthenticationService(
            membershipClient: membershipClient,
            deviceClient: deviceClient
        )

        self.e2eEncryptionService = E2EEncryptionService(
            identityService: identityService
        )

        self.authenticationService = AuthenticationService(
            networkProvider: networkProvider,
            identityKeys: identityService,
            connectivityService: connectivityService,
            localization: localizationService,
            opaqueAuthService: opaqueAuthService,
            onIdentityKeysGenerated: { [weak self] in
                await self?.updateIdentityKeysStatus()
            }
        )

        self.registrationService = RegistrationService(
            networkProvider: networkProvider,
            connectivityService: connectivityService,
            localization: localizationService,
            identityService: identityService,
            opaqueAuthService: opaqueAuthService,
            onIdentityKeysGenerated: { [weak self] in
                await self?.updateIdentityKeysStatus()
            }
        )

        self.passwordRecoveryService = PasswordRecoveryService(
            networkProvider: networkProvider,
            connectivityService: connectivityService,
            localization: localizationService
        )

        self.logoutService = LogoutService(
            networkProvider: networkProvider,
            stateManager: stateManager,
            router: router,
            connectivityService: connectivityService,
            localization: localizationService,
            identityService: identityService,
            secureStorage: secureStorage
        )

        self.welcomeService = WelcomeService(
            localization: localizationService
        )

        self.signInService = SignInService(
            authenticationService: authenticationService,
            localization: localizationService
        )

        Log.info("[ServiceContainer] All services initialized successfully")
    }

    func initialize() async {
        Log.info("[ServiceContainer] Starting application initialization")

        let keysExist = await checkForIdentityKeys()
        await MainActor.run {
            self.hasIdentityKeys = keysExist
        }

        if hasIdentityKeys {
            Log.info("[ServiceContainer] Identity keys found - using authenticated connection")
            networkProvider.setConnectionMode(.authenticated)
        } else {
            Log.info("[ServiceContainer] No identity keys found - using unauthenticated connection")
            networkProvider.setConnectionMode(.unauthenticated)
        }

        await stateManager.transitionToAnonymous()

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        await router.transitionFromSplash(isAuthenticated: stateManager.isAuthenticated)

        Log.info("[ServiceContainer] Application initialization complete")
    }

    private func checkForIdentityKeys() async -> Bool {
        do {
            let hasMasterKey = try await identityService.hasMasterKeyHandle()

            if hasMasterKey {
                Log.info("[ServiceContainer] Found master key handle")
                return true
            }

            return false

        } catch {
            Log.error("[ServiceContainer] Error checking for identity keys: \(error.localizedDescription)")
            return false
        }
    }

    func updateIdentityKeysStatus() async {
        let keysExist = await checkForIdentityKeys()
        await MainActor.run {
            self.hasIdentityKeys = keysExist
        }

        if keysExist {
            Log.info("[ServiceContainer] Identity keys status updated - authenticated connection now available")
            networkProvider.setConnectionMode(.authenticated)
        }
    }
}
