import Combine
import Foundation

@MainActor
public final class SessionStateManager: ObservableObject {

    @Published public private(set) var sessionState: SessionState = .unauthenticated
    @Published public private(set) var currentUser: UserInfo?
    @Published public private(set) var deviceInfo: DeviceInfo?

    private let keychainStorage: KeychainStorage
    private let secureStorage: SecureStorage

    public enum SessionState: String, Codable {
        case unauthenticated
        case authenticating
        case authenticated
        case suspended
        case expired
    }

    public struct UserInfo: Codable {
        public let membershipId: String
        public let mobileNumber: String
        public let deviceId: String
        public let createdAt: Date
        public var lastActiveAt: Date

        public init(
            membershipId: String,
            mobileNumber: String,
            deviceId: String,
            createdAt: Date = Date(),
            lastActiveAt: Date = Date()
        ) {
            self.membershipId = membershipId
            self.mobileNumber = mobileNumber
            self.deviceId = deviceId
            self.createdAt = createdAt
            self.lastActiveAt = lastActiveAt
        }
    }

    public struct DeviceInfo: Codable {
        public let deviceId: String
        public let deviceName: String
        public let systemVersion: String
        public let appVersion: String
        public let registeredAt: Date

        public init(
            deviceId: String,
            deviceName: String,
            systemVersion: String,
            appVersion: String,
            registeredAt: Date = Date()
        ) {
            self.deviceId = deviceId
            self.deviceName = deviceName
            self.systemVersion = systemVersion
            self.appVersion = appVersion
            self.registeredAt = registeredAt
        }
    }

    private struct PersistedSession: Codable {
        let state: SessionState
        let user: UserInfo?
        let device: DeviceInfo?
        let persistedAt: Date
    }

    public init(
        keychainStorage: KeychainStorage? = nil,
        secureStorage: SecureStorage? = nil
    ) {
        self.keychainStorage = keychainStorage ?? KeychainStorage()

        if let provided = secureStorage {
            self.secureStorage = provided
        } else {
            guard let defaultStorage = try? SecureStorage() else {
                Log.error("[SessionStateManager] Failed to initialize SecureStorage")
                fatalError("Failed to initialize SecureStorage - check file system permissions")
            }
            self.secureStorage = defaultStorage
        }

        restoreSession()
    }

    public func startSession(user: UserInfo, device: DeviceInfo) {
        self.currentUser = user
        self.deviceInfo = device
        self.sessionState = .authenticated

        persistSession()

        Log.info("[SessionState] [OK] Started session for user: \(user.membershipId)")
    }

    public func updateState(_ newState: SessionState) {
        guard sessionState != newState else { return }

        let oldState = sessionState
        sessionState = newState

        persistSession()

        Log.info("[SessionState] State changed: \(oldState.rawValue) → \(newState.rawValue)")
    }

    public func updateLastActivity() {
        guard var user = currentUser else { return }

        user.lastActiveAt = Date()
        currentUser = user

        persistSession()

        Log.debug("[SessionState] Updated last activity")
    }

    public func endSession() {
        sessionState = .unauthenticated
        currentUser = nil
        deviceInfo = nil

        clearPersistedSession()

        Log.info("[SessionState] [ERROR] Session ended")
    }

    public func suspendSession() {
        guard sessionState == .authenticated else { return }

        updateState(.suspended)

        Log.info("[SessionState] ⏸ Session suspended")
    }

    public func resumeSession() {
        guard sessionState == .suspended else { return }

        updateState(.authenticated)
        updateLastActivity()

        Log.info("[SessionState]  Session resumed")
    }

    public func expireSession() {
        updateState(.expired)

        Log.warning("[SessionState] ⏰ Session expired")
    }

    public func isSessionValid() -> Bool {
        return sessionState == .authenticated && currentUser != nil
    }

    public func isSessionExpired(timeout: TimeInterval = 3600) -> Bool {
        guard let user = currentUser else { return true }

        let timeSinceActivity = Date().timeIntervalSince(user.lastActiveAt)
        return timeSinceActivity > timeout
    }

    private func persistSession() {
        let session = PersistedSession(
            state: sessionState,
            user: currentUser,
            device: deviceInfo,
            persistedAt: Date()
        )

        do {
            try secureStorage.store(session, forKey: "current_session")
            Log.debug("[SessionState]  Persisted session state")
        } catch {
            Log.error("[SessionState] Failed to persist session: \(error)")
        }
    }

    private func restoreSession() {
        do {
            let session: PersistedSession = try secureStorage.retrieve(forKey: "current_session")

            let sessionAge = Date().timeIntervalSince(session.persistedAt)
            if sessionAge > 7 * 24 * 3600 {
                Log.warning("[SessionState] Persisted session too old, ignoring")
                clearPersistedSession()
                return
            }

            sessionState = session.state
            currentUser = session.user
            deviceInfo = session.device

            if sessionState == .authenticated {
                if isSessionExpired() {
                    expireSession()
                }
            }

            Log.info("[SessionState] [OK] Restored session state: \(sessionState.rawValue)")

        } catch SecureStorageError.notFound {
            Log.debug("[SessionState] No persisted session found")
        } catch {
            Log.error("[SessionState] Failed to restore session: \(error)")
        }
    }

    private func clearPersistedSession() {
        do {
            try secureStorage.delete(forKey: "current_session")
            Log.debug("[SessionState]  Cleared persisted session")
        } catch {
            Log.error("[SessionState] Failed to clear persisted session: \(error)")
        }
    }

    public func updateDeviceInfo(_ device: DeviceInfo) {
        deviceInfo = device
        persistSession()

        Log.debug("[SessionState] Updated device info")
    }

    public func getCurrentDeviceId() -> String? {
        return deviceInfo?.deviceId
    }

    public func updateUserInfo(_ user: UserInfo) {
        currentUser = user
        persistSession()

        Log.debug("[SessionState] Updated user info")
    }

    public func getCurrentMembershipId() -> String? {
        return currentUser?.membershipId
    }

    public func getStatistics() -> SessionStatistics {
        let sessionDuration: TimeInterval?
        if let user = currentUser {
            sessionDuration = Date().timeIntervalSince(user.createdAt)
        } else {
            sessionDuration = nil
        }

        let inactiveDuration: TimeInterval?
        if let user = currentUser {
            inactiveDuration = Date().timeIntervalSince(user.lastActiveAt)
        } else {
            inactiveDuration = nil
        }

        return SessionStatistics(
            state: sessionState,
            isValid: isSessionValid(),
            isExpired: isSessionExpired(),
            sessionDuration: sessionDuration,
            inactiveDuration: inactiveDuration,
            membershipId: currentUser?.membershipId,
            deviceId: deviceInfo?.deviceId
        )
    }
}

public struct SessionStatistics {
    public let state: SessionStateManager.SessionState
    public let isValid: Bool
    public let isExpired: Bool
    public let sessionDuration: TimeInterval?
    public let inactiveDuration: TimeInterval?
    public let membershipId: String?
    public let deviceId: String?

    public var sessionDurationFormatted: String {
        guard let duration = sessionDuration else { return "N/A" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    public var inactiveDurationFormatted: String {
        guard let duration = inactiveDuration else { return "N/A" }
        let minutes = Int(duration) / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            return "\(hours)h \(minutes % 60)m"
        }
    }
}
