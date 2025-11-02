import Combine
import EcliptixCore
import EcliptixNetworking
import EcliptixProto
import EcliptixSecurity
import Foundation
import Observation
import SwiftProtobuf

public enum LogoutReason: String, Codable {
    case userRequested = "UserRequested"
    case sessionExpired = "SessionExpired"
    case securityViolation = "SecurityViolation"
    case accountDeleted = "AccountDeleted"
    case deviceRevoked = "DeviceRevoked"
    case forceLogout = "ForceLogout"
}

public enum LogoutScope: String, Codable {
    case thisDevice = "ThisDevice"
    case allDevices = "AllDevices"
}

@MainActor
@Observable
public final class LogoutService {

    public var isLoggingOut: Bool = false
    public var errorMessage: String?

    private let networkProvider: NetworkProvider
    private let stateManager: ApplicationStateManager
    private let router: ApplicationRouter
    private let connectivityService: ConnectivityService
    private let localization: LocalizationService
    private let identityService: IdentityService
    private let secureStorage: ApplicationSecureStorageProvider
    private let logoutKeyDerivation: LogoutKeyDerivationService

    public private(set) var logoutCommand: DefaultAsyncCommand<LogoutReason, Void>

    private var cancellables = Set<AnyCancellable>()

    public init(
        networkProvider: NetworkProvider,
        stateManager: ApplicationStateManager,
        router: ApplicationRouter,
        connectivityService: ConnectivityService,
        localization: LocalizationService,
        identityService: IdentityService,
        secureStorage: ApplicationSecureStorageProvider,
        logoutKeyDerivation: LogoutKeyDerivationService = LogoutKeyDerivationService()
    ) {
        self.networkProvider = networkProvider
        self.stateManager = stateManager
        self.router = router
        self.connectivityService = connectivityService
        self.localization = localization
        self.identityService = identityService
        self.secureStorage = secureStorage
        self.logoutKeyDerivation = logoutKeyDerivation

        self.logoutCommand = DefaultAsyncCommand.createAction { _ in }

        setupCommands()
    }

    private func setupCommands() {
        self.logoutCommand = DefaultAsyncCommand.createAction { [weak self] reason in
            guard let self = self else { return }
            let result = await self.performLogout(reason: reason)
            switch result {
            case .success:
                return
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                throw error
            }
        }
    }

    public func logout(reason: LogoutReason = .userRequested) async {
        await logoutCommand.execute(with: reason)
    }

    private func performLogout(reason: LogoutReason) async -> Result<Void, Error> {
        isLoggingOut = true
        errorMessage = nil
        defer { isLoggingOut = false }

        Log.info("[LogoutService] Starting logout. Reason: \(reason.rawValue)")

        guard let membershipId = stateManager.currentMembershipId else {
            let error = LogoutError.noActiveSession(
                localization[LocalizationKeys.Error.noActiveSession]
            )
            errorMessage = error.localizedDescription
            Log.warning("[LogoutService] No active session found")
            return .failure(error)
        }

        Log.info("[LogoutService] Logging out membership: \(membershipId)")

        guard let masterKeyHandle = try? await identityService.loadMasterKeyHandle() else {
            Log.warning("[LogoutService] No master key found, proceeding with local logout only")
            await performLocalCleanup(membershipId: membershipId, reason: reason)
            return .success(())
        }

        let logoutRequest: Data
        do {
            logoutRequest = try await createLogoutRequest(
                membershipId: membershipId,
                masterKey: masterKeyHandle.keyMaterial,
                reason: reason,
                scope: .thisDevice
            )
        } catch {
            Log.error("[LogoutService] Failed to create logout request: \(error.localizedDescription)")

            await performLocalCleanup(membershipId: membershipId, reason: reason)
            return .success(())
        }

        let serverResult = await notifyServerLogout(logoutRequest)

        switch serverResult {
        case .success:
            Log.info("[LogoutService] Server logout succeeded")

        case .failure(let error):
            Log.warning("[LogoutService] Server logout failed (will proceed with local): \(error.localizedDescription)")

        }

        await performLocalCleanup(membershipId: membershipId, reason: reason)

        Log.info("[LogoutService] Logout completed successfully")
        return .success(())
    }

    private func notifyServerLogout(_ request: Data) async -> Result<Void, Error> {
        guard !connectivityService.isOffline else {
            Log.warning("[LogoutService] Network outage detected, skipping server notification")
            return .failure(LogoutError.networkUnavailable(
                localization[LocalizationKeys.NetworkNotification.NoInternet.description]
            ))
        }

        let connectId: UInt32 = 0

        let result = await networkProvider.executeUnaryRequest(
            connectId: connectId,
            serviceType: .logout,
            plainBuffer: request,
            allowDuplicates: false,
            waitForRecovery: false
        ) { responseData in
            try await self.processLogoutResponse(responseData)
        }

        switch result {
        case .success:
            return .success(())

        case .failure(let networkFailure):
            Log.error("[LogoutService] Server logout failed: \(networkFailure.message)")
            return .failure(LogoutError.networkError(networkFailure.message))
        }
    }

    private func performLocalCleanup(membershipId: String, reason: LogoutReason) async {
        Log.info("[LogoutService] Starting local cleanup for: \(membershipId)")

        await clearSessionState()

        await clearIdentityKeys()

        await clearSecureStorage(membershipId: membershipId)

        await stateManager.transitionToAnonymous()

        await router.navigateToAuthentication()

        Log.info("[LogoutService] Local cleanup completed")
    }

    private func clearSessionState() async {
        do {
            try await stateManager.clearSession()
            Log.debug("[LogoutService] Cleared session state")
        } catch {
            Log.warning("[LogoutService] Failed to clear session state: \(error.localizedDescription)")
        }
    }

    private func clearIdentityKeys() async {
        do {
            try await identityService.deleteMasterKeyHandle()
            try await identityService.deleteIdentityKeyBundle()
            Log.debug("[LogoutService] Cleared identity keys")
        } catch {
            Log.warning("[LogoutService] Failed to clear identity keys: \(error.localizedDescription)")
        }
    }

    private func clearSecureStorage(membershipId: String) async {
        do {
            guard let membershipUUID = UUID(uuidString: membershipId) else {
                Log.warning("[LogoutService] Invalid membership UUID format: \(membershipId)")
                return
            }

            let protocolStateStorage = secureStorage.protocolStateStorage
            try await protocolStateStorage.deleteAllStates(membershipId: membershipUUID)

            let skippedKeysStorage = secureStorage.skippedMessageKeysStorage
            try await skippedKeysStorage.deleteAllKeys(membershipId: membershipUUID)

            Log.debug("[LogoutService] Cleared secure storage for: \(membershipId)")
        } catch {
            Log.warning("[LogoutService] Failed to clear secure storage: \(error.localizedDescription)")
        }
    }

    private func createLogoutRequest(
        membershipId: String,
        masterKey: Data,
        reason: LogoutReason,
        scope: LogoutScope
    ) async throws -> Data {
        guard let membershipUUID = UUID(uuidString: membershipId) else {
            throw LogoutError.unknown("Invalid membership UUID format")
        }

        let logoutKey = try logoutKeyDerivation.deriveLogoutKey(
            from: masterKey,
            membershipId: membershipUUID
        )

        let timestamp = Date()
        let logoutToken = try logoutKeyDerivation.generateLogoutToken(
            using: logoutKey,
            membershipId: membershipUUID,
            timestamp: timestamp
        )

        var uuidBytes = membershipUUID.uuid
        let membershipIdData = withUnsafeBytes(of: &uuidBytes) { Data($0) }

        var request = Ecliptix_Proto_Membership_LogoutRequest()
        request.membershipIdentifier = membershipIdData
        request.logoutReason = reason.rawValue
        request.timestamp = Int64(timestamp.timeIntervalSince1970 * 1000)
        request.hmacProof = logoutToken
        request.scope = scope == .thisDevice ? .thisDevice : .allDevices

        return try request.serializedData()
    }

    private func processLogoutResponse(_ data: Data) async throws {

        let response = try Ecliptix_Proto_Membership_LogoutResponse(serializedData: data)

        Log.info("[LogoutService] Logout response: result=\(response.result), timestamp=\(response.serverTimestamp)")

        switch response.result {
        case .succeeded:
            Log.info("[LogoutService] Logout succeeded")

        case .alreadyLoggedOut:
            Log.info("[LogoutService] Already logged out")

        case .sessionNotFound:
            Log.warning("[LogoutService] Session not found on server")

        case .invalidTimestamp:
            throw LogoutError.unknown("Invalid timestamp in logout request")

        case .invalidHmac:
            throw LogoutError.unknown("Invalid HMAC proof in logout request")

        case .failed:
            throw LogoutError.unknown("Logout failed on server")

        case .UNRECOGNIZED(let value):
            throw LogoutError.unknown("Unknown logout result: \(value)")
        }

        if !response.revocationProof.isEmpty {
            Log.debug("[LogoutService] Received revocation proof: \(response.revocationProof.count) bytes")
        }
    }
}

public enum LogoutError: LocalizedError {
    case noActiveSession(String)
    case networkUnavailable(String)
    case networkError(String)
    case cleanupFailed(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveSession(let message),
             .networkUnavailable(let message),
             .networkError(let message),
             .cleanupFailed(let message),
             .unknown(let message):
            return message
        }
    }
}

public extension LogoutService {

    func quickLogout() async {
        await logout(reason: .userRequested)
    }

    func forceLogout() async {
        await logout(reason: .securityViolation)
    }

    func sessionExpiredLogout() async {
        await logout(reason: .sessionExpired)
    }
}
