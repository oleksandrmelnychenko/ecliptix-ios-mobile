import Foundation
import Combine
import EcliptixCore

// MARK: - Connection Health Monitor
/// Monitors health of individual connections and provides health metrics
/// Migrated from: Ecliptix.Core/Services/Network/Health/ConnectionHealthMonitor.cs
@MainActor
public final class ConnectionHealthMonitor {

    // MARK: - Health State

    /// Health status for a connection
    public enum HealthStatus: String {
        case healthy        // No issues
        case degraded       // Some failures, but functional
        case unhealthy      // Frequent failures
        case critical       // Unusable
    }

    /// Health information for a connection
    public struct ConnectionHealth {
        public let connectId: UInt32
        public let status: HealthStatus
        public let successRate: Double
        public let averageLatency: TimeInterval
        public let failureCount: Int
        public let successCount: Int
        public let lastSuccessTime: Date?
        public let lastFailureTime: Date?
        public let consecutiveFailures: Int

        public var isHealthy: Bool {
            return status == .healthy
        }

        public var isDegraded: Bool {
            return status == .degraded
        }

        public var isUnhealthy: Bool {
            return status == .unhealthy || status == .critical
        }
    }

    // MARK: - Properties

    private let configuration: HealthMonitorConfiguration

    /// Health tracking per connection
    private var connectionHealth: [UInt32: ConnectionHealthTracker] = [:]
    private let healthLock = NSLock()

    /// Publisher for health status changes
    public let healthStatusPublisher = PassthroughSubject<ConnectionHealth, Never>()

    /// Cleanup timer
    private var cleanupTimer: Timer?

    // MARK: - Health Tracker

    /// Internal tracker for connection health
    private class ConnectionHealthTracker {
        let connectId: UInt32
        var status: HealthStatus = .healthy

        var successCount: Int = 0
        var failureCount: Int = 0
        var consecutiveFailures: Int = 0

        var latencySamples: [TimeInterval] = []
        var maxLatencySamples: Int = 100

        var lastSuccessTime: Date?
        var lastFailureTime: Date?
        var firstTrackingTime: Date = Date()

        init(connectId: UInt32) {
            self.connectId = connectId
        }

        var totalRequests: Int {
            return successCount + failureCount
        }

        var successRate: Double {
            guard totalRequests > 0 else { return 1.0 }
            return Double(successCount) / Double(totalRequests)
        }

        var averageLatency: TimeInterval {
            guard !latencySamples.isEmpty else { return 0.0 }
            return latencySamples.reduce(0.0, +) / Double(latencySamples.count)
        }

        func addLatencySample(_ latency: TimeInterval) {
            latencySamples.append(latency)
            if latencySamples.count > maxLatencySamples {
                latencySamples.removeFirst()
            }
        }

        func updateStatus(config: HealthMonitorConfiguration) {
            // Determine health status based on metrics
            if consecutiveFailures >= config.criticalConsecutiveFailures {
                status = .critical
            } else if consecutiveFailures >= config.unhealthyConsecutiveFailures {
                status = .unhealthy
            } else if successRate < config.degradedSuccessRateThreshold {
                status = .degraded
            } else if averageLatency > config.degradedLatencyThreshold {
                status = .degraded
            } else {
                status = .healthy
            }
        }

        func toConnectionHealth() -> ConnectionHealth {
            return ConnectionHealth(
                connectId: connectId,
                status: status,
                successRate: successRate,
                averageLatency: averageLatency,
                failureCount: failureCount,
                successCount: successCount,
                lastSuccessTime: lastSuccessTime,
                lastFailureTime: lastFailureTime,
                consecutiveFailures: consecutiveFailures
            )
        }
    }

    // MARK: - Initialization

    public init(configuration: HealthMonitorConfiguration = .default) {
        self.configuration = configuration

        // Start cleanup timer
        startCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    // MARK: - Health Tracking

    /// Records a successful request
    /// Migrated from: RecordSuccess()
    public func recordSuccess(connectId: UInt32, latency: TimeInterval) {
        healthLock.lock()
        defer { healthLock.unlock() }

        let tracker = getOrCreateTracker(connectId: connectId)

        tracker.successCount += 1
        tracker.consecutiveFailures = 0
        tracker.lastSuccessTime = Date()
        tracker.addLatencySample(latency)

        let previousStatus = tracker.status
        tracker.updateStatus(config: configuration)

        if previousStatus != tracker.status {
            let health = tracker.toConnectionHealth()
            Log.info("[HealthMonitor] 📊 Connection \(connectId) status: \(previousStatus.rawValue) → \(tracker.status.rawValue)")
            healthStatusPublisher.send(health)
        }
    }

    /// Records a failed request
    /// Migrated from: RecordFailure()
    public func recordFailure(connectId: UInt32, error: NetworkFailure) {
        healthLock.lock()
        defer { healthLock.unlock() }

        let tracker = getOrCreateTracker(connectId: connectId)

        tracker.failureCount += 1
        tracker.consecutiveFailures += 1
        tracker.lastFailureTime = Date()

        let previousStatus = tracker.status
        tracker.updateStatus(config: configuration)

        if previousStatus != tracker.status {
            let health = tracker.toConnectionHealth()
            Log.warning("[HealthMonitor] 📊 Connection \(connectId) status: \(previousStatus.rawValue) → \(tracker.status.rawValue)")
            healthStatusPublisher.send(health)
        }
    }

    /// Gets health status for a connection
    /// Migrated from: GetHealthStatus()
    public func getHealth(connectId: UInt32) -> ConnectionHealth? {
        healthLock.lock()
        defer { healthLock.unlock() }

        return connectionHealth[connectId]?.toConnectionHealth()
    }

    /// Gets health status for all connections
    public func getAllHealth() -> [ConnectionHealth] {
        healthLock.lock()
        defer { healthLock.unlock() }

        return connectionHealth.values.map { $0.toConnectionHealth() }
    }

    /// Checks if connection is healthy
    public func isHealthy(connectId: UInt32) -> Bool {
        healthLock.lock()
        defer { healthLock.unlock() }

        guard let tracker = connectionHealth[connectId] else {
            return true // Unknown connection = assumed healthy
        }

        return tracker.status == .healthy
    }

    /// Resets health tracking for a connection
    /// Migrated from: ResetHealth()
    public func resetHealth(connectId: UInt32) {
        healthLock.lock()
        defer { healthLock.unlock() }

        connectionHealth.removeValue(forKey: connectId)
        Log.info("[HealthMonitor] 🔄 Reset health for connection \(connectId)")
    }

    /// Resets all health tracking
    public func resetAllHealth() {
        healthLock.lock()
        defer { healthLock.unlock() }

        connectionHealth.removeAll()
        Log.info("[HealthMonitor] 🔄 Reset all connection health")
    }

    // MARK: - Helpers

    private func getOrCreateTracker(connectId: UInt32) -> ConnectionHealthTracker {
        if let tracker = connectionHealth[connectId] {
            return tracker
        }

        let tracker = ConnectionHealthTracker(connectId: connectId)
        connectionHealth[connectId] = tracker
        return tracker
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            self?.cleanupStaleConnections()
        }
    }

    private func cleanupStaleConnections() {
        healthLock.lock()
        defer { healthLock.unlock() }

        let cutoff = Date().addingTimeInterval(-configuration.staleConnectionTimeout)
        var removed = 0

        for (connectId, tracker) in connectionHealth {
            // Remove if no activity for stale timeout
            let lastActivity = max(tracker.lastSuccessTime ?? tracker.firstTrackingTime,
                                   tracker.lastFailureTime ?? tracker.firstTrackingTime)

            if lastActivity < cutoff {
                connectionHealth.removeValue(forKey: connectId)
                removed += 1
            }
        }

        if removed > 0 {
            Log.info("[HealthMonitor] 🧹 Cleaned up \(removed) stale connections")
        }
    }

    // MARK: - Statistics

    /// Returns overall health statistics
    public func getStatistics() -> HealthStatistics {
        healthLock.lock()
        defer { healthLock.unlock() }

        let allHealth = connectionHealth.values.map { $0.toConnectionHealth() }

        let healthy = allHealth.filter { $0.status == .healthy }.count
        let degraded = allHealth.filter { $0.status == .degraded }.count
        let unhealthy = allHealth.filter { $0.status == .unhealthy }.count
        let critical = allHealth.filter { $0.status == .critical }.count

        let totalSuccess = allHealth.reduce(0) { $0 + $1.successCount }
        let totalFailure = allHealth.reduce(0) { $0 + $1.failureCount }
        let totalRequests = totalSuccess + totalFailure

        let overallSuccessRate = totalRequests > 0 ? Double(totalSuccess) / Double(totalRequests) : 1.0

        return HealthStatistics(
            totalConnections: allHealth.count,
            healthyConnections: healthy,
            degradedConnections: degraded,
            unhealthyConnections: unhealthy,
            criticalConnections: critical,
            overallSuccessRate: overallSuccessRate,
            totalSuccesses: totalSuccess,
            totalFailures: totalFailure
        )
    }
}

// MARK: - Configuration

/// Configuration for health monitoring
/// Migrated from: HealthMonitorConfiguration.cs
public struct HealthMonitorConfiguration {

    /// Success rate threshold for degraded status (e.g., 0.9 = 90%)
    public let degradedSuccessRateThreshold: Double

    /// Latency threshold for degraded status (in seconds)
    public let degradedLatencyThreshold: TimeInterval

    /// Consecutive failures for unhealthy status
    public let unhealthyConsecutiveFailures: Int

    /// Consecutive failures for critical status
    public let criticalConsecutiveFailures: Int

    /// Cleanup interval for stale connections (in seconds)
    public let cleanupInterval: TimeInterval

    /// Timeout for considering a connection stale (in seconds)
    public let staleConnectionTimeout: TimeInterval

    public init(
        degradedSuccessRateThreshold: Double = 0.85,
        degradedLatencyThreshold: TimeInterval = 5.0,
        unhealthyConsecutiveFailures: Int = 3,
        criticalConsecutiveFailures: Int = 5,
        cleanupInterval: TimeInterval = 300.0,
        staleConnectionTimeout: TimeInterval = 600.0
    ) {
        self.degradedSuccessRateThreshold = degradedSuccessRateThreshold
        self.degradedLatencyThreshold = degradedLatencyThreshold
        self.unhealthyConsecutiveFailures = unhealthyConsecutiveFailures
        self.criticalConsecutiveFailures = criticalConsecutiveFailures
        self.cleanupInterval = cleanupInterval
        self.staleConnectionTimeout = staleConnectionTimeout
    }

    // MARK: - Presets

    /// Default configuration
    public static let `default` = HealthMonitorConfiguration()

    /// Strict configuration (lower thresholds)
    public static let strict = HealthMonitorConfiguration(
        degradedSuccessRateThreshold: 0.95,
        degradedLatencyThreshold: 3.0,
        unhealthyConsecutiveFailures: 2,
        criticalConsecutiveFailures: 3
    )

    /// Relaxed configuration (higher thresholds)
    public static let relaxed = HealthMonitorConfiguration(
        degradedSuccessRateThreshold: 0.70,
        degradedLatencyThreshold: 10.0,
        unhealthyConsecutiveFailures: 5,
        criticalConsecutiveFailures: 10
    )
}

// MARK: - Statistics

/// Overall health statistics
public struct HealthStatistics {
    public let totalConnections: Int
    public let healthyConnections: Int
    public let degradedConnections: Int
    public let unhealthyConnections: Int
    public let criticalConnections: Int
    public let overallSuccessRate: Double
    public let totalSuccesses: Int
    public let totalFailures: Int

    public var healthyPercentage: Double {
        guard totalConnections > 0 else { return 1.0 }
        return Double(healthyConnections) / Double(totalConnections)
    }
}
