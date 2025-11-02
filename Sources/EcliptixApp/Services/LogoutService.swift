import Combine
import EcliptixCore
import Foundation
import Observation

public enum LogoutReason: String, Codable, Sendable {
    case userRequested = "UserRequested"
    case sessionExpired = "SessionExpired"
    case securityViolation = "SecurityViolation"
    case accountDeleted = "AccountDeleted"
    case deviceRevoked = "DeviceRevoked"
    case forceLogout = "ForceLogout"
}

public enum LogoutScope: String, Codable, Sendable {
    case thisDevice = "ThisDevice"
    case allDevices = "AllDevices"
}

@MainActor
public final class LogoutService {

    public var isLoggingOut: Bool = false
    public var errorMessage: String?

    public let logoutCommand: DefaultAsyncCommand<LogoutReason, Void>

    public init(
        networkProvider: Any,
        stateManager: ApplicationStateManager,
        router: Any,
        connectivityService: ConnectivityService,
        localization: LocalizationService,
        identityService: Any,
        secureStorage: Any
    ) {
        self.logoutCommand = DefaultAsyncCommand { reason in
            Log.info("[LogoutService] Logout requested: \(reason.rawValue)")
        }
    }
}
