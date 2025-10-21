import Foundation
import Combine

// MARK: - Session State Manager
/// Manages application session state with persistence
/// Migrated from: Ecliptix.Core/Infrastructure/Session/SessionStateManager.cs
@MainActor
public final class SessionStateManager: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var sessionState: SessionState = .unauthenticated
    @Published public private(set) var currentUser: UserInfo?
    @Published public private(set) var deviceInfo: DeviceInfo?

    // MARK: - Properties

    private let keychainStorage: KeychainStorage
    private let secureStorage: SecureStorage

    // MARK: - Session State

    /// Application session state
    public enum SessionState: String, Codable {
        case unauthenticated
        case authenticating
        case authenticated
        case suspended
        case expired
    }

    // MARK: - User Info

    /// Current user information
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

    // MARK: - Device Info

    /// Device information
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

    // MARK: - Persisted Session

    /// Complete persisted session data
    private struct PersistedSession: Codable {
        let state: SessionState
        let user: UserInfo?
        let device: DeviceInfo?
        let persistedAt: Date
    }

    // MARK: - Initialization

    public init(
        keychainStorage: KeychainStorage = KeychainStorage(),
        secureStorage: SecureStorage? = nil
    ) {
        self.keychainStorage = keychainStorage
        self.secureStorage = (try? secureStorage) ?? (try! SecureStorage())

        // Restore session on init
        restoreSession()
    }

    // MARK: - Session Management

    /// Starts a new authenticated session
    /// Migrated from: StartSessionAsync()
    public func startSession(user: UserInfo, device: DeviceInfo) {
        self.currentUser = user
        self.deviceInfo = device
        self.sessionState = .authenticated

        persistSession()

        Log.info("[SessionState] ✅ Started session for user: \(user.membershipId)")
    }

    /// Updates current session state
    /// Migrated from: UpdateSessionStateAsync()
    public func updateState(_ newState: SessionState) {
        guard sessionState != newState else { return }

        let oldState = sessionState
        sessionState = newState

        persistSession()

        Log.info("[SessionState] State changed: \(oldState.rawValue) → \(newState.rawValue)")
    }

    /// Updates user activity timestamp
    /// Migrated from: UpdateLastActivityAsync()
    public func updateLastActivity() {
        guard var user = currentUser else { return }

        user.lastActiveAt = Date()
        currentUser = user

        persistSession()

        Log.debug("[SessionState] Updated last activity")
    }

    /// Ends the current session
    /// Migrated from: EndSessionAsync()
    public func endSession() {
        sessionState = .unauthenticated
        currentUser = nil
        deviceInfo = nil

        clearPersistedSession()

        Log.info("[SessionState] 🔴 Session ended")
    }

    /// Suspends the current session
    /// Migrated from: SuspendSessionAsync()
    public func suspendSession() {
        guard sessionState == .authenticated else { return }

        updateState(.suspended)

        Log.info("[SessionState] ⏸️ Session suspended")
    }

    /// Resumes a suspended session
    /// Migrated from: ResumeSessionAsync()
    public func resumeSession() {
        guard sessionState == .suspended else { return }

        updateState(.authenticated)
        updateLastActivity()

        Log.info("[SessionState] ▶️ Session resumed")
    }

    /// Marks session as expired
    /// Migrated from: ExpireSessionAsync()
    public func expireSession() {
        updateState(.expired)

        Log.warning("[SessionState] ⏰ Session expired")
    }

    // MARK: - Session Validation

    /// Checks if session is valid
    /// Migrated from: IsSessionValid()
    public func isSessionValid() -> Bool {
        return sessionState == .authenticated && currentUser != nil
    }

    /// Checks if session is expired
    public func isSessionExpired(timeout: TimeInterval = 3600) -> Bool {
        guard let user = currentUser else { return true }

        let timeSinceActivity = Date().timeIntervalSince(user.lastActiveAt)
        return timeSinceActivity > timeout
    }

    // MARK: - Persistence

    /// Persists current session state
    /// Migrated from: PersistSessionAsync()
    private func persistSession() {
        let session = PersistedSession(
            state: sessionState,
            user: currentUser,
            device: deviceInfo,
            persistedAt: Date()
        )

        do {
            try secureStorage.store(session, forKey: "current_session")
            Log.debug("[SessionState] 💾 Persisted session state")
        } catch {
            Log.error("[SessionState] Failed to persist session: \(error)")
        }
    }

    /// Restores session from persistence
    /// Migrated from: RestoreSessionAsync()
    private func restoreSession() {
        do {
            let session: PersistedSession = try secureStorage.retrieve(forKey: "current_session")

            // Check if session is too old (e.g., > 7 days)
            let sessionAge = Date().timeIntervalSince(session.persistedAt)
            if sessionAge > 7 * 24 * 3600 {
                Log.warning("[SessionState] Persisted session too old, ignoring")
                clearPersistedSession()
                return
            }

            // Restore session
            sessionState = session.state
            currentUser = session.user
            deviceInfo = session.device

            // If authenticated, check if expired
            if sessionState == .authenticated {
                if isSessionExpired() {
                    expireSession()
                }
            }

            Log.info("[SessionState] ✅ Restored session state: \(sessionState.rawValue)")

        } catch SecureStorageError.notFound {
            Log.debug("[SessionState] No persisted session found")
        } catch {
            Log.error("[SessionState] Failed to restore session: \(error)")
        }
    }

    /// Clears persisted session
    /// Migrated from: ClearPersistedSessionAsync()
    private func clearPersistedSession() {
        do {
            try secureStorage.delete(forKey: "current_session")
            Log.debug("[SessionState] 🗑️ Cleared persisted session")
        } catch {
            Log.error("[SessionState] Failed to clear persisted session: \(error)")
        }
    }

    // MARK: - Device Management

    /// Updates device information
    /// Migrated from: UpdateDeviceInfoAsync()
    public func updateDeviceInfo(_ device: DeviceInfo) {
        deviceInfo = device
        persistSession()

        Log.debug("[SessionState] Updated device info")
    }

    /// Gets current device ID
    public func getCurrentDeviceId() -> String? {
        return deviceInfo?.deviceId
    }

    // MARK: - User Management

    /// Updates user information
    /// Migrated from: UpdateUserInfoAsync()
    public func updateUserInfo(_ user: UserInfo) {
        currentUser = user
        persistSession()

        Log.debug("[SessionState] Updated user info")
    }

    /// Gets current membership ID
    public func getCurrentMembershipId() -> String? {
        return currentUser?.membershipId
    }

    // MARK: - Session Statistics

    /// Returns session statistics
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

// MARK: - Statistics

/// Session statistics
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
