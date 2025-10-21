import Foundation
import EcliptixCore

// MARK: - Request Timeout Manager
/// Manages timeouts for network requests with per-operation configuration
/// Migrated from: Ecliptix.Core/Services/Network/Infrastructure/RequestTimeoutManager.cs
@MainActor
public final class RequestTimeoutManager {

    // MARK: - Timeout Entry

    /// Active timeout tracking entry
    private class TimeoutEntry {
        let requestId: String
        let startTime: Date
        let timeoutDuration: TimeInterval
        let onTimeout: () -> Void

        init(
            requestId: String,
            timeoutDuration: TimeInterval,
            onTimeout: @escaping () -> Void
        ) {
            self.requestId = requestId
            self.startTime = Date()
            self.timeoutDuration = timeoutDuration
            self.onTimeout = onTimeout
        }

        var isTimedOut: Bool {
            return Date().timeIntervalSince(startTime) >= timeoutDuration
        }

        var remainingTime: TimeInterval {
            let elapsed = Date().timeIntervalSince(startTime)
            return max(0, timeoutDuration - elapsed)
        }

        var elapsedTime: TimeInterval {
            return Date().timeIntervalSince(startTime)
        }
    }

    // MARK: - Properties

    private let configuration: TimeoutConfiguration

    /// Active timeout entries
    private var activeTimeouts: [String: TimeoutEntry] = [:]
    private let timeoutsLock = NSLock()

    /// Timeout check timer
    private var checkTimer: Timer?

    /// Statistics
    private var totalTimeouts: Int = 0
    private var totalRequests: Int = 0

    // MARK: - Initialization

    public init(configuration: TimeoutConfiguration = .default) {
        self.configuration = configuration

        // Start timeout check timer
        startCheckTimer()
    }

    deinit {
        checkTimer?.invalidate()
    }

    // MARK: - Timeout Tracking

    /// Starts tracking timeout for a request
    /// Migrated from: StartTrackingRequest()
    public func startTracking(
        requestId: String,
        timeout: TimeInterval? = nil,
        onTimeout: @escaping () -> Void
    ) {
        timeoutsLock.lock()
        defer { timeoutsLock.unlock() }

        let timeoutDuration = timeout ?? configuration.defaultTimeout

        let entry = TimeoutEntry(
            requestId: requestId,
            timeoutDuration: timeoutDuration,
            onTimeout: onTimeout
        )

        activeTimeouts[requestId] = entry
        totalRequests += 1

        Log.debug("[TimeoutManager] ⏱️ Tracking request: \(requestId) (timeout: \(String(format: "%.1f", timeoutDuration))s)")
    }

    /// Stops tracking timeout for a request (call when request completes)
    /// Migrated from: StopTrackingRequest()
    public func stopTracking(requestId: String) {
        timeoutsLock.lock()
        defer { timeoutsLock.unlock() }

        if let entry = activeTimeouts.removeValue(forKey: requestId) {
            Log.debug("[TimeoutManager] ✅ Completed request: \(requestId) (elapsed: \(String(format: "%.2f", entry.elapsedTime))s)")
        }
    }

    /// Extends timeout for an existing request
    /// Migrated from: ExtendTimeout()
    public func extendTimeout(requestId: String, additionalTime: TimeInterval) {
        timeoutsLock.lock()
        defer { timeoutsLock.unlock() }

        guard let entry = activeTimeouts[requestId] else {
            return
        }

        // Create new entry with extended timeout
        let newEntry = TimeoutEntry(
            requestId: requestId,
            timeoutDuration: entry.timeoutDuration + additionalTime,
            onTimeout: entry.onTimeout
        )

        activeTimeouts[requestId] = newEntry
        Log.debug("[TimeoutManager] ⏱️ Extended timeout for: \(requestId) (+\(String(format: "%.1f", additionalTime))s)")
    }

    /// Checks if request has timed out
    /// Migrated from: IsTimedOut()
    public func isTimedOut(requestId: String) -> Bool {
        timeoutsLock.lock()
        defer { timeoutsLock.unlock() }

        guard let entry = activeTimeouts[requestId] else {
            return false
        }

        return entry.isTimedOut
    }

    /// Gets remaining time for a request
    public func getRemainingTime(requestId: String) -> TimeInterval? {
        timeoutsLock.lock()
        defer { timeoutsLock.unlock() }

        return activeTimeouts[requestId]?.remainingTime
    }

    // MARK: - Timeout Checking

    private func startCheckTimer() {
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkTimeouts()
        }
    }

    private func checkTimeouts() {
        timeoutsLock.lock()
        var timedOutEntries: [TimeoutEntry] = []

        for (requestId, entry) in activeTimeouts {
            if entry.isTimedOut {
                timedOutEntries.append(entry)
                activeTimeouts.removeValue(forKey: requestId)
            }
        }

        timeoutsLock.unlock()

        // Execute timeout callbacks outside of lock
        for entry in timedOutEntries {
            totalTimeouts += 1
            Log.warning("[TimeoutManager] ⏰ Request TIMED OUT: \(entry.requestId) (duration: \(String(format: "%.2f", entry.timeoutDuration))s)")
            entry.onTimeout()
        }
    }

    // MARK: - Batch Operations

    /// Cancels all active timeouts
    /// Migrated from: CancelAllTimeouts()
    public func cancelAll() {
        timeoutsLock.lock()
        defer { timeoutsLock.unlock() }

        let count = activeTimeouts.count
        activeTimeouts.removeAll()

        if count > 0 {
            Log.info("[TimeoutManager] 🛑 Cancelled all \(count) active timeouts")
        }
    }

    /// Gets count of active timeouts
    public var activeTimeoutCount: Int {
        timeoutsLock.lock()
        defer { timeoutsLock.unlock() }

        return activeTimeouts.count
    }

    // MARK: - Statistics

    /// Returns timeout statistics
    public func getStatistics() -> TimeoutStatistics {
        timeoutsLock.lock()
        defer { timeoutsLock.unlock() }

        let timeoutRate = totalRequests > 0 ? Double(totalTimeouts) / Double(totalRequests) : 0.0

        return TimeoutStatistics(
            activeTimeouts: activeTimeouts.count,
            totalTimeouts: totalTimeouts,
            totalRequests: totalRequests,
            timeoutRate: timeoutRate
        )
    }

    /// Resets statistics
    public func resetStatistics() {
        timeoutsLock.lock()
        defer { timeoutsLock.unlock() }

        totalTimeouts = 0
        totalRequests = 0

        Log.debug("[TimeoutManager] 📊 Reset timeout statistics")
    }

    // MARK: - Helper: Execute with Timeout

    /// Executes an operation with timeout
    /// Migrated from: ExecuteWithTimeoutAsync()
    public func execute<T>(
        requestId: String,
        timeout: TimeInterval? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {

        return try await withThrowingTaskGroup(of: T.self) { group in
            let timeoutDuration = timeout ?? configuration.defaultTimeout

            // Add operation task
            group.addTask {
                return try await operation()
            }

            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutDuration * 1_000_000_000))
                throw TimeoutError.timeout(duration: timeoutDuration)
            }

            // Start tracking
            startTracking(requestId: requestId, timeout: timeoutDuration) {
                // Timeout callback - cancel group
                group.cancelAll()
            }

            defer {
                // Stop tracking when done
                stopTracking(requestId: requestId)
                group.cancelAll()
            }

            // Return first result
            guard let result = try await group.next() else {
                throw TimeoutError.cancelled
            }

            return result
        }
    }
}

// MARK: - Configuration

/// Configuration for timeout management
/// Migrated from: TimeoutConfiguration.cs
public struct TimeoutConfiguration {

    /// Default timeout duration (in seconds)
    public let defaultTimeout: TimeInterval

    /// Interval for checking timeouts (in seconds)
    public let checkInterval: TimeInterval

    /// Whether to enable timeout tracking
    public let enabled: Bool

    public init(
        defaultTimeout: TimeInterval = 30.0,
        checkInterval: TimeInterval = 1.0,
        enabled: Bool = true
    ) {
        self.defaultTimeout = defaultTimeout
        self.checkInterval = checkInterval
        self.enabled = enabled
    }

    // MARK: - Presets

    /// Default configuration (30s timeout, 1s check interval)
    public static let `default` = TimeoutConfiguration()

    /// Short timeouts (10s timeout, 0.5s check interval)
    public static let short = TimeoutConfiguration(
        defaultTimeout: 10.0,
        checkInterval: 0.5
    )

    /// Long timeouts (60s timeout, 2s check interval)
    public static let long = TimeoutConfiguration(
        defaultTimeout: 60.0,
        checkInterval: 2.0
    )

    /// Disabled
    public static let disabled = TimeoutConfiguration(
        defaultTimeout: 0,
        checkInterval: 0,
        enabled: false
    )
}

// MARK: - Statistics

/// Timeout statistics
public struct TimeoutStatistics {
    public let activeTimeouts: Int
    public let totalTimeouts: Int
    public let totalRequests: Int
    public let timeoutRate: Double

    public var timeoutPercentage: Double {
        return timeoutRate * 100.0
    }
}

// MARK: - Errors

/// Timeout-related errors
public enum TimeoutError: LocalizedError {
    case timeout(duration: TimeInterval)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .timeout(let duration):
            return "Operation timed out after \(String(format: "%.1f", duration))s"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}
