import Combine
import EcliptixCore
import Foundation

@MainActor
public final class ConnectionHealthMonitor {

    public enum HealthStatus: String {
        case healthy
        case degraded
        case unhealthy
        case critical
    }

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

    private let configuration: HealthMonitorConfiguration

    private var connectionHealth: [UInt32: ConnectionHealthTracker] = [:]

    public let healthStatusPublisher = PassthroughSubject<ConnectionHealth, Never>()

    nonisolated(unsafe) private var cleanupTimer: Timer?

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

    public init(configuration: HealthMonitorConfiguration = .default) {
        self.configuration = configuration

        startCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    public func recordSuccess(connectId: UInt32, latency: TimeInterval) {
        let tracker = getOrCreateTracker(connectId: connectId)

        tracker.successCount += 1
        tracker.consecutiveFailures = 0
        tracker.lastSuccessTime = Date()
        tracker.addLatencySample(latency)

        let previousStatus = tracker.status
        tracker.updateStatus(config: configuration)

        if previousStatus != tracker.status {
            let health = tracker.toConnectionHealth()
            Log.info("[HealthMonitor]  Connection \(connectId) status: \(previousStatus.rawValue) → \(tracker.status.rawValue)")
            healthStatusPublisher.send(health)
        }
    }

    public func recordFailure(connectId: UInt32, error: NetworkFailure) {
        let tracker = getOrCreateTracker(connectId: connectId)

        tracker.failureCount += 1
        tracker.consecutiveFailures += 1
        tracker.lastFailureTime = Date()

        let previousStatus = tracker.status
        tracker.updateStatus(config: configuration)

        if previousStatus != tracker.status {
            let health = tracker.toConnectionHealth()
            Log.warning("[HealthMonitor]  Connection \(connectId) status: \(previousStatus.rawValue) → \(tracker.status.rawValue)")
            healthStatusPublisher.send(health)
        }
    }

    public func getHealth(connectId: UInt32) -> ConnectionHealth? {
        return connectionHealth[connectId]?.toConnectionHealth()
    }

    public func getAllHealth() -> [ConnectionHealth] {
        return connectionHealth.values.map { $0.toConnectionHealth() }
    }

    public func isHealthy(connectId: UInt32) -> Bool {
        guard let tracker = connectionHealth[connectId] else {
            return true
        }

        return tracker.status == .healthy
    }

    public func isConnectionHealthy(connectId: UInt32) -> Bool {
        return isHealthy(connectId: connectId)
    }

    public func markConnectionHealthy(connectId: UInt32) {
        guard let tracker = connectionHealth[connectId] else {
            return
        }

        tracker.consecutiveFailures = 0
        let previousStatus = tracker.status
        tracker.updateStatus(config: configuration)

        if previousStatus != tracker.status {
            let health = tracker.toConnectionHealth()
            Log.info("[HealthMonitor] [OK] Connection \(connectId) marked healthy: \(previousStatus.rawValue) → \(tracker.status.rawValue)")
            healthStatusPublisher.send(health)
        }
    }

    public func resetHealth(connectId: UInt32) {
        connectionHealth.removeValue(forKey: connectId)
        Log.info("[HealthMonitor]  Reset health for connection \(connectId)")
    }

    public func resetAllHealth() {
        connectionHealth.removeAll()
        Log.info("[HealthMonitor]  Reset all connection health")
    }

    private func getOrCreateTracker(connectId: UInt32) -> ConnectionHealthTracker {
        if let tracker = connectionHealth[connectId] {
            return tracker
        }

        let tracker = ConnectionHealthTracker(connectId: connectId)
        connectionHealth[connectId] = tracker
        return tracker
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStaleConnections()
            }
        }
    }

    private func cleanupStaleConnections() {
        let cutoff = Date().addingTimeInterval(-configuration.staleConnectionTimeout)
        var removed = 0

        for (connectId, tracker) in connectionHealth {

            let lastActivity = max(tracker.lastSuccessTime ?? tracker.firstTrackingTime,
                                   tracker.lastFailureTime ?? tracker.firstTrackingTime)

            if lastActivity < cutoff {
                connectionHealth.removeValue(forKey: connectId)
                removed += 1
            }
        }

        if removed > 0 {
            Log.info("[HealthMonitor]  Cleaned up \(removed) stale connections")
        }
    }

    public func getStatistics() -> HealthStatistics {
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

public struct HealthMonitorConfiguration: Sendable {

    public let degradedSuccessRateThreshold: Double

    public let degradedLatencyThreshold: TimeInterval

    public let unhealthyConsecutiveFailures: Int

    public let criticalConsecutiveFailures: Int

    public let cleanupInterval: TimeInterval

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

    public static let `default` = HealthMonitorConfiguration()

    public static let strict = HealthMonitorConfiguration(
        degradedSuccessRateThreshold: 0.95,
        degradedLatencyThreshold: 3.0,
        unhealthyConsecutiveFailures: 2,
        criticalConsecutiveFailures: 3
    )

    public static let relaxed = HealthMonitorConfiguration(
        degradedSuccessRateThreshold: 0.70,
        degradedLatencyThreshold: 10.0,
        unhealthyConsecutiveFailures: 5,
        criticalConsecutiveFailures: 10
    )
}

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
