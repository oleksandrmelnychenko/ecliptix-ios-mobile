import EcliptixSecurity
import Foundation
import protocol EcliptixCore.ApplicationInstanceSettingsStorage
import struct EcliptixCore.ApplicationInstanceSettings
import struct EcliptixCore.DefaultCultureSettings
import struct EcliptixCore.IpCountry
import struct EcliptixCore.MembershipInfo
import var EcliptixCore.Log

public typealias AppSettings = ApplicationInstanceSettings

public actor ApplicationBootstrap {

    private let networkProvider: NetworkProvider
    private let settingsStorage: ApplicationInstanceSettingsStorage
    private let protocolStateStorage: SecureProtocolStateStorage
    private let identityService: IdentityService

    private let ipGeolocationTimeoutSeconds: TimeInterval = 10

    public init(
        networkProvider: NetworkProvider,
        settingsStorage: ApplicationInstanceSettingsStorage,
        protocolStateStorage: SecureProtocolStateStorage,
        identityService: IdentityService
    ) {
        self.networkProvider = networkProvider
        self.settingsStorage = settingsStorage
        self.protocolStateStorage = protocolStateStorage
        self.identityService = identityService
    }

    public func initialize(culture: String = DefaultCultureSettings.defaultCultureCode) async -> Result<(connectId: UInt32, isAuthenticated: Bool), NetworkFailure> {

        Log.info("[Bootstrap] [START] Starting application initialization")

        let settingsResult = await initializeApplicationSettings(culture: culture)
        guard case .success(let (settings, isNewInstance)) = settingsResult else {
            if case .failure(let error) = settingsResult {
                Log.error("[Bootstrap] [FAILED] Failed to initialize settings: \(error.message)")
                return .failure(error)
            }
            return .failure(NetworkFailure(type: .unknown, message: "Settings initialization failed"))
        }

        Log.info("[Bootstrap] [OK] Settings initialized - New instance: \(isNewInstance), AppInstanceId: \(settings.appInstanceId)")

        let channelResult = await ensureSecrecyChannel(settings: settings, isNewInstance: isNewInstance)
        guard case .success(let connectId) = channelResult else {
            if case .failure(let error) = channelResult {
                Log.error("[Bootstrap] [FAILED] Failed to establish secure channel: \(error.message)")
                return .failure(error)
            }
            return .failure(NetworkFailure(type: .unknown, message: "Channel establishment failed"))
        }

        Log.info("[Bootstrap] [OK] Secure channel established - ConnectId: \(connectId)")

        Log.info("[Bootstrap]  Registering device - ConnectId: \(connectId)")
        let registrationResult = await registerDevice(connectId: connectId, settings: settings)
        guard case .success = registrationResult else {
            if case .failure(let error) = registrationResult {
                Log.error("[Bootstrap] [FAILED] Device registration failed: \(error.message)")
                return .failure(error)
            }
            return .failure(NetworkFailure(type: .unknown, message: "Device registration failed"))
        }

        Log.info("[Bootstrap] [OK] Device registered successfully")

        let isAuthenticated = settings.membership != nil

        Log.info("[Bootstrap]  Initialization complete - ConnectId: \(connectId), Authenticated: \(isAuthenticated)")

        return .success((connectId, isAuthenticated))
    }

    private func initializeApplicationSettings(culture: String) async -> Result<(settings: AppSettings, isNewInstance: Bool), NetworkFailure> {
        do {
            if let existingSettings = try await settingsStorage.loadSettings() {
                Log.info("[Bootstrap] Found existing application settings")
                return .success((existingSettings, false))
            }

            let newSettings = AppSettings(
                appInstanceId: UUID(),
                deviceId: UUID(),
                culture: culture
            )

            try await settingsStorage.saveSettings(newSettings)

            Log.info("[Bootstrap] Created new application settings - AppInstanceId: \(newSettings.appInstanceId)")

            return .success((newSettings, true))

        } catch {
            Log.error("[Bootstrap] Failed to initialize settings: \(error.localizedDescription)")
            return .failure(NetworkFailure(
                type: .unknown,
                message: "Failed to initialize application settings: \(error.localizedDescription)"
            ))
        }
    }

    private func ensureSecrecyChannel(
        settings: AppSettings,
        isNewInstance: Bool
    ) async -> Result<UInt32, NetworkFailure> {

        let connectId = await MainActor.run {
            networkProvider.computeUniqueConnectId(
                appInstanceId: settings.appInstanceId,
                deviceId: settings.deviceId,
                exchangeType: .dataCenterEphemeralConnect
            )
        }

        Log.info("[Bootstrap] Computed ConnectId: \(connectId)")

        let membershipId = settings.membership?.uniqueIdentifier

        if !isNewInstance {
            Log.info("[Bootstrap] Attempting to restore session state")

            let restoreResult = await tryRestoreSessionState(
                connectId: connectId,
                settings: settings
            )

            switch restoreResult {
            case .success(true):
                Log.info("[Bootstrap] [OK] Session restored successfully")
                return .success(connectId)

            case .success(false):
                Log.info("[Bootstrap] No session to restore, will establish new channel")

            case .failure(let error):
                Log.warning("[Bootstrap] Session restoration failed: \(error.message), will establish new channel")
            }
        }

        var shouldUseAuthenticatedProtocol = false
        var masterKeyHandle: SecureMemoryHandle?

        if let membershipId = membershipId {
            Log.info("[Bootstrap] Checking prerequisites for authenticated protocol - MembershipId: \(membershipId)")

            let hasStoredIdentity = await identityService.hasStoredIdentity(membershipId: membershipId)
            Log.info("[Bootstrap] HasStoredIdentity: \(hasStoredIdentity)")

            if hasStoredIdentity {

                masterKeyHandle = await tryReconstructMasterKey(
                    membershipId: membershipId,
                    settings: settings
                )

                if masterKeyHandle != nil {
                    Log.info("[Bootstrap] [OK] All prerequisites met for authenticated protocol")
                    shouldUseAuthenticatedProtocol = true
                } else {
                    Log.warning("[Bootstrap] Failed to reconstruct master key, will use anonymous protocol")
                }
            } else {
                Log.info("[Bootstrap] No stored identity found, will use anonymous protocol")
            }
        } else {
            Log.info("[Bootstrap] No membership identifier, will use anonymous protocol")
        }

        if shouldUseAuthenticatedProtocol, let masterKeyHandle = masterKeyHandle, let membershipId = membershipId {
            Log.info("[Bootstrap]  Creating authenticated protocol - ConnectId: \(connectId)")

            let recreateResult = await networkProvider.recreateProtocolWithMasterKey(
                masterKeyHandle: masterKeyHandle,
                membershipId: membershipId,
                connectId: connectId,
                appInstanceId: settings.appInstanceId,
                deviceId: settings.deviceId
            )

            masterKeyHandle.dispose()

            switch recreateResult {
            case .success:
                Log.info("[Bootstrap] [OK] Authenticated protocol created successfully")

            case .failure(let error):
                Log.warning("[Bootstrap] Authenticated protocol creation failed: \(error.message), falling back to anonymous")
                await initializeProtocolWithoutIdentity(settings: settings, connectId: connectId)
            }
        } else {
            Log.info("[Bootstrap] [UNSECURE] Creating anonymous protocol - ConnectId: \(connectId)")
            await initializeProtocolWithoutIdentity(settings: settings, connectId: connectId)
        }

        return await establishAndSaveSecrecyChannel(
            connectId: connectId,
            membershipId: membershipId
        )
    }

    private func tryRestoreSessionState(
        connectId: UInt32,
        settings: AppSettings
    ) async -> Result<Bool, NetworkFailure> {

        guard let membershipId = settings.membership?.uniqueIdentifier else {
            Log.info("[Bootstrap] No membership ID, cannot restore session")
            return .success(false)
        }

        do {

            let stateData = try await protocolStateStorage.loadState(
                connectId: "\(connectId)",
                membershipId: membershipId
            )

            guard let stateData = stateData else {
                Log.info("[Bootstrap] No stored protocol state found")
                return .success(false)
            }

            let restoreResult = await networkProvider.restoreSession(
                connectId: connectId,
                stateData: stateData,
                membershipId: membershipId
            )

            switch restoreResult {
            case .success:
                Log.info("[Bootstrap] [OK] Session state restored successfully")
                return .success(true)

            case .failure(let error):
                Log.warning("[Bootstrap] Failed to restore session: \(error.message)")
                return .failure(error)
            }

        } catch {
            Log.error("[Bootstrap] Failed to load session state: \(error.localizedDescription)")
            return .failure(NetworkFailure(
                type: .unknown,
                message: "Failed to load session state: \(error.localizedDescription)"
            ))
        }
    }

    private func initializeProtocolWithoutIdentity(
        settings: AppSettings,
        connectId: UInt32
    ) async {

        if settings.membership != nil {
            do {
                try await settingsStorage.updateMembership(nil)
                Log.info("[Bootstrap] Cleared membership from settings")
            } catch {
                Log.warning("[Bootstrap] Failed to clear membership: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            networkProvider.initiateEcliptixProtocol(
                settings: settings,
                connectId: connectId
            )
        }
    }

    private func establishAndSaveSecrecyChannel(
        connectId: UInt32,
        membershipId: UUID?
    ) async -> Result<UInt32, NetworkFailure> {

        Log.info("[Bootstrap] Establishing secrecy channel - ConnectId: \(connectId)")

        let establishResult = await networkProvider.establishSecrecyChannel(connectId: connectId)

        switch establishResult {
        case .success(let sessionState):
            Log.info("[Bootstrap] [OK] Secrecy channel established")

            if let membershipId = membershipId {
                do {
                    try await protocolStateStorage.saveState(
                        sessionState,
                        connectId: "\(connectId)",
                        membershipId: membershipId
                    )
                    Log.info("[Bootstrap] [OK] Session state saved")
                } catch {
                    Log.warning("[Bootstrap] Failed to save session state: \(error.localizedDescription)")
                }
            } else {
                Log.info("[Bootstrap] No membership ID, skipping state save")
            }

            return .success(connectId)

        case .failure(let error):
            Log.error("[Bootstrap] Failed to establish secrecy channel: \(error.message)")
            return .failure(error)
        }
    }

    private func tryReconstructMasterKey(
        membershipId: UUID,
        settings: AppSettings
    ) async -> SecureMemoryHandle? {

        Log.info("[Bootstrap] Attempting to reconstruct master key")

        do {
            let masterKeyHandle = try await identityService.loadMasterKeyHandle(membershipId: membershipId)
            Log.info("[Bootstrap] [OK] Master key loaded successfully")
            return masterKeyHandle

        } catch {
            Log.warning("[Bootstrap] Failed to load master key: \(error.localizedDescription)")
            return nil
        }
    }

    private func registerDevice(
        connectId: UInt32,
        settings: AppSettings
    ) async -> Result<Void, NetworkFailure> {

        let result = await networkProvider.registerDevice(
            connectId: connectId,
            appInstanceId: settings.appInstanceId,
            deviceId: settings.deviceId,
            culture: settings.culture
        )

        switch result {
        case .success:
            Log.info("[Bootstrap] [OK] Device registration successful")
            return .success(())

        case .failure(let error):
            Log.error("[Bootstrap] Device registration failed: \(error.message)")
            return .failure(error)
        }
    }
}
