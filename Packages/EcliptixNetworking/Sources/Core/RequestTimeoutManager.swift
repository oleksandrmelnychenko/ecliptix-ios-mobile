import EcliptixCore
import Foundation

@MainActor
public final class RequestTimeoutManager {

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

    private let configuration: TimeoutConfiguration

    private var activeTimeouts: [String: TimeoutEntry] = [:]

    nonisolated(unsafe) private var checkTimer: Timer?

    private var totalTimeouts: Int = 0
    private var totalRequests: Int = 0

    public init(configuration: TimeoutConfiguration = .default) {
        self.configuration = configuration

        startCheckTimer()
    }

    deinit {
        checkTimer?.invalidate()
    }

    public func startTracking(
        requestId: String,
        timeout: TimeInterval? = nil,
        onTimeout: @escaping () -> Void
    ) {
        let timeoutDuration = timeout ?? configuration.defaultTimeout

        let entry = TimeoutEntry(
            requestId: requestId,
            timeoutDuration: timeoutDuration,
            onTimeout: onTimeout
        )

        activeTimeouts[requestId] = entry
        totalRequests += 1

        Log.debug("[TimeoutManager] ⏱ Tracking request: \(requestId) (timeout: \(String(format: "%.1f", timeoutDuration))s)")
    }

    public func stopTracking(requestId: String) {
        if let entry = activeTimeouts.removeValue(forKey: requestId) {
            Log.debug("[TimeoutManager] [OK] Completed request: \(requestId) (elapsed: \(String(format: "%.2f", entry.elapsedTime))s)")
        }
    }

    public func extendTimeout(requestId: String, additionalTime: TimeInterval) {
        guard let entry = activeTimeouts[requestId] else {
            return
        }

        let newEntry = TimeoutEntry(
            requestId: requestId,
            timeoutDuration: entry.timeoutDuration + additionalTime,
            onTimeout: entry.onTimeout
        )

        activeTimeouts[requestId] = newEntry
        Log.debug("[TimeoutManager] ⏱ Extended timeout for: \(requestId) (+\(String(format: "%.1f", additionalTime))s)")
    }

    public func isTimedOut(requestId: String) -> Bool {
        guard let entry = activeTimeouts[requestId] else {
            return false
        }

        return entry.isTimedOut
    }

    public func getRemainingTime(requestId: String) -> TimeInterval? {
        return activeTimeouts[requestId]?.remainingTime
    }

    private func startCheckTimer() {
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.checkInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkTimeouts()
            }
        }

        RunLoop.main.add(checkTimer!, forMode: .common)
    }

    private func checkTimeouts() {
        let timedOutEntries = activeTimeouts.values.filter { $0.isTimedOut }

        for entry in timedOutEntries {
            activeTimeouts.removeValue(forKey: entry.requestId)
        }

        for entry in timedOutEntries {
            totalTimeouts += 1
            Log.warning("[TimeoutManager] ⏰ Request TIMED OUT: \(entry.requestId) (duration: \(String(format: "%.2f", entry.timeoutDuration))s)")
            entry.onTimeout()
        }
    }

    public func cancelAll() {
        let count = activeTimeouts.count
        activeTimeouts.removeAll()

        if count > 0 {
            Log.info("[TimeoutManager]  Cancelled all \(count) active timeouts")
        }
    }

    public var activeTimeoutCount: Int {
        return activeTimeouts.count
    }

    public func getStatistics() -> TimeoutStatistics {
        let timeoutRate = totalRequests > 0 ? Double(totalTimeouts) / Double(totalRequests) : 0.0

        return TimeoutStatistics(
            activeTimeouts: activeTimeouts.count,
            totalTimeouts: totalTimeouts,
            totalRequests: totalRequests,
            timeoutRate: timeoutRate
        )
    }

    public func resetStatistics() {
        totalTimeouts = 0
        totalRequests = 0

        Log.debug("[TimeoutManager]  Reset timeout statistics")
    }

    public func execute<T: Sendable>(
        requestId: String,
        timeout: TimeInterval? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {

        return try await withThrowingTaskGroup(of: T.self) { group in
            let timeoutDuration = timeout ?? configuration.defaultTimeout

            group.addTask {
                return try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutDuration * 1_000_000_000))
                throw TimeoutError.timeout(duration: timeoutDuration)
            }

            startTracking(requestId: requestId, timeout: timeoutDuration, onTimeout: {})

            defer {
                stopTracking(requestId: requestId)
                group.cancelAll()
            }

            guard let result = try await group.next() else {
                throw TimeoutError.cancelled
            }

            return result
        }
    }
}

public struct TimeoutConfiguration: Sendable {

    public let defaultTimeout: TimeInterval

    public let checkInterval: TimeInterval

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

    public static let `default` = TimeoutConfiguration()

    public static let short = TimeoutConfiguration(
        defaultTimeout: 10.0,
        checkInterval: 0.5
    )

    public static let long = TimeoutConfiguration(
        defaultTimeout: 60.0,
        checkInterval: 2.0
    )

    public static let disabled = TimeoutConfiguration(
        defaultTimeout: 0,
        checkInterval: 0,
        enabled: false
    )
}

public struct TimeoutStatistics {
    public let activeTimeouts: Int
    public let totalTimeouts: Int
    public let totalRequests: Int
    public let timeoutRate: Double

    public var timeoutPercentage: Double {
        return timeoutRate * 100.0
    }
}

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
