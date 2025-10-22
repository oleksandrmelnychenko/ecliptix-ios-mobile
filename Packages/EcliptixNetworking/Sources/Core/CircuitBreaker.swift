import Foundation
import EcliptixCore

// MARK: - Circuit Breaker
/// Implements the Circuit Breaker pattern to prevent cascading failures
/// Migrated from: Ecliptix.Core/Services/Network/Resilience/CircuitBreaker.cs
///
/// States:
/// - Closed: Normal operation, requests pass through
/// - Open: Failure threshold exceeded, requests fail fast
/// - Half-Open: Testing if service recovered, limited requests allowed
@MainActor
public final class CircuitBreaker {

    // MARK: - State

    /// Circuit breaker state
    public enum State: String {
        case closed     // Normal operation
        case open       // Failing fast
        case halfOpen   // Testing recovery
    }

    /// Current state of the circuit breaker
    private(set) var state: State = .closed

    // MARK: - Configuration

    private let configuration: CircuitBreakerConfiguration

    // MARK: - Metrics

    /// Consecutive failure count
    private var consecutiveFailures: Int = 0

    /// Consecutive success count (in half-open state)
    private var consecutiveSuccesses: Int = 0

    /// Last state transition time
    private var lastStateTransition: Date = Date()

    /// Total failures since last reset
    private var totalFailures: Int = 0

    /// Total successes since last reset
    private var totalSuccesses: Int = 0

    /// Connection-specific circuit breakers
    private var connectionCircuits: [UInt32: ConnectionCircuitState] = [:]
    private let connectionsLock = NSLock()

    // MARK: - Types

    /// Per-connection circuit state
    private class ConnectionCircuitState {
        let connectId: UInt32
        var state: State
        var consecutiveFailures: Int
        var lastStateTransition: Date
        var lastFailureTime: Date?

        init(connectId: UInt32) {
            self.connectId = connectId
            self.state = .closed
            self.consecutiveFailures = 0
            self.lastStateTransition = Date()
        }
    }

    // MARK: - Initialization

    public init(configuration: CircuitBreakerConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Execute with Circuit Breaker

    /// Executes an operation with circuit breaker protection
    /// Migrated from: ExecuteAsync()
    public func execute<T>(
        connectId: UInt32? = nil,
        operationName: String,
        operation: @escaping () async throws -> Result<T, NetworkFailure>
    ) async -> Result<T, NetworkFailure> {

        // Check if circuit is open (global or connection-specific)
        if let connectId = connectId {
            if isCircuitOpen(connectId: connectId) {
                Log.warning("[CircuitBreaker] 🔴 Circuit OPEN for connection \(connectId) - failing fast: \(operationName)")
                return .failure(NetworkFailure(
                    type: .dataCenterNotResponding,
                    message: "Circuit breaker is open - service temporarily unavailable",
                    shouldRetry: false
                ))
            }
        } else {
            if state == .open && !shouldAttemptReset() {
                Log.warning("[CircuitBreaker] 🔴 Circuit OPEN globally - failing fast: \(operationName)")
                return .failure(NetworkFailure(
                    type: .dataCenterNotResponding,
                    message: "Circuit breaker is open - service temporarily unavailable",
                    shouldRetry: false
                ))
            }
        }

        // Execute operation
        do {
            let result = try await operation()

            switch result {
            case .success:
                // Record success
                if let connectId = connectId {
                    recordSuccess(connectId: connectId)
                } else {
                    recordSuccess()
                }
                return result

            case .failure(let error):
                // Record failure
                if let connectId = connectId {
                    recordFailure(connectId: connectId, error: error)
                } else {
                    recordFailure(error: error)
                }
                return result
            }

        } catch {
            // Unexpected error
            let failure = NetworkFailure(
                type: .unknown,
                message: "Circuit breaker caught unexpected error: \(error.localizedDescription)",
                shouldRetry: false
            )

            if let connectId = connectId {
                recordFailure(connectId: connectId, error: failure)
            } else {
                recordFailure(error: failure)
            }

            return .failure(failure)
        }
    }

    // MARK: - State Management (Global)

    /// Records a successful operation
    /// Migrated from: RecordSuccess()
    private func recordSuccess() {
        totalSuccesses += 1

        switch state {
        case .halfOpen:
            // Track consecutive successes in half-open state
            consecutiveSuccesses += 1

            if consecutiveSuccesses >= configuration.successThreshold {
                // Success threshold met - close circuit
                transitionTo(.closed)
                consecutiveFailures = 0
                consecutiveSuccesses = 0
                Log.info("[CircuitBreaker] ✅ Circuit CLOSED - service recovered (\(consecutiveSuccesses) successes)")
            }

        case .closed:
            // Reset failure count on success
            if consecutiveFailures > 0 {
                consecutiveFailures = 0
            }

        case .open:
            // Should not reach here, but reset if we do
            transitionTo(.halfOpen)
        }
    }

    /// Records a failed operation
    /// Migrated from: RecordFailure()
    private func recordFailure(error: NetworkFailure) {
        totalFailures += 1

        // Only count retriable failures
        guard error.shouldRetry else {
            return
        }

        consecutiveFailures += 1

        switch state {
        case .closed:
            // Check if failure threshold exceeded
            if consecutiveFailures >= configuration.failureThreshold {
                transitionTo(.open)
                Log.warning("[CircuitBreaker] 🔴 Circuit OPEN - failure threshold exceeded (\(consecutiveFailures) failures)")
            }

        case .halfOpen:
            // Any failure in half-open state reopens circuit
            transitionTo(.open)
            consecutiveSuccesses = 0
            Log.warning("[CircuitBreaker] 🔴 Circuit RE-OPENED - service still failing")

        case .open:
            // Already open, just track metric
            break
        }
    }

    /// Transitions to a new state
    private func transitionTo(_ newState: State) {
        guard state != newState else { return }

        let oldState = state
        state = newState
        lastStateTransition = Date()

        Log.info("[CircuitBreaker] 🔄 State transition: \(oldState.rawValue) → \(newState.rawValue)")
    }

    /// Checks if enough time has passed to attempt reset
    private func shouldAttemptReset() -> Bool {
        guard state == .open else { return false }

        let timeSinceOpen = Date().timeIntervalSince(lastStateTransition)
        if timeSinceOpen >= configuration.openStateDuration {
            // Attempt reset to half-open
            transitionTo(.halfOpen)
            return true
        }

        return false
    }

    // MARK: - State Management (Per-Connection)

    /// Records success for a specific connection
    private func recordSuccess(connectId: UInt32) {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        guard let circuit = connectionCircuits[connectId] else {
            return
        }

        if circuit.state == .halfOpen {
            // Close circuit after successful recovery test
            circuit.state = .closed
            circuit.consecutiveFailures = 0
            circuit.lastStateTransition = Date()
            Log.info("[CircuitBreaker] ✅ Circuit CLOSED for connection \(connectId)")
        } else if circuit.state == .closed {
            // Reset failure count
            circuit.consecutiveFailures = 0
        }
    }

    /// Records failure for a specific connection
    private func recordFailure(connectId: UInt32, error: NetworkFailure) {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        guard error.shouldRetry else {
            return
        }

        let circuit = connectionCircuits[connectId] ?? ConnectionCircuitState(connectId: connectId)
        connectionCircuits[connectId] = circuit

        circuit.consecutiveFailures += 1
        circuit.lastFailureTime = Date()

        if circuit.state == .closed && circuit.consecutiveFailures >= configuration.failureThreshold {
            // Open circuit
            circuit.state = .open
            circuit.lastStateTransition = Date()
            Log.warning("[CircuitBreaker] 🔴 Circuit OPEN for connection \(connectId) - \(circuit.consecutiveFailures) failures")

        } else if circuit.state == .halfOpen {
            // Re-open circuit
            circuit.state = .open
            circuit.lastStateTransition = Date()
            Log.warning("[CircuitBreaker] 🔴 Circuit RE-OPENED for connection \(connectId)")
        }
    }

    /// Checks if circuit is open for a specific connection
    private func isCircuitOpen(connectId: UInt32) -> Bool {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        guard let circuit = connectionCircuits[connectId] else {
            return false // No circuit = closed
        }

        if circuit.state == .open {
            // Check if enough time has passed to attempt reset
            let timeSinceOpen = Date().timeIntervalSince(circuit.lastStateTransition)
            if timeSinceOpen >= configuration.openStateDuration {
                // Attempt reset to half-open
                circuit.state = .halfOpen
                circuit.lastStateTransition = Date()
                Log.info("[CircuitBreaker] 🟡 Circuit HALF-OPEN for connection \(connectId) - testing recovery")
                return false
            }
            return true
        }

        return false
    }

    // MARK: - Manual Control

    /// Manually opens the circuit breaker
    /// Migrated from: Trip()
    public func trip() {
        transitionTo(.open)
        Log.warning("[CircuitBreaker] 🔴 Circuit manually TRIPPED")
    }

    /// Manually closes the circuit breaker
    /// Migrated from: Reset()
    public func reset() {
        transitionTo(.closed)
        consecutiveFailures = 0
        consecutiveSuccesses = 0
        totalFailures = 0
        totalSuccesses = 0

        // Reset all connection circuits
        connectionsLock.lock()
        connectionCircuits.removeAll()
        connectionsLock.unlock()

        Log.info("[CircuitBreaker] ✅ Circuit manually RESET")
    }

    /// Resets circuit for a specific connection
    public func resetConnection(_ connectId: UInt32) {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        if let circuit = connectionCircuits[connectId] {
            circuit.state = .closed
            circuit.consecutiveFailures = 0
            circuit.lastStateTransition = Date()
            Log.info("[CircuitBreaker] ✅ Circuit RESET for connection \(connectId)")
        }
    }

    // MARK: - Metrics

    /// Returns current circuit breaker metrics
    public func getMetrics() -> CircuitBreakerMetrics {
        return CircuitBreakerMetrics(
            state: state,
            consecutiveFailures: consecutiveFailures,
            consecutiveSuccesses: consecutiveSuccesses,
            totalFailures: totalFailures,
            totalSuccesses: totalSuccesses,
            timeSinceLastTransition: Date().timeIntervalSince(lastStateTransition)
        )
    }

    /// Returns metrics for a specific connection
    public func getConnectionMetrics(connectId: UInt32) -> ConnectionCircuitMetrics? {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }

        guard let circuit = connectionCircuits[connectId] else {
            return nil
        }

        return ConnectionCircuitMetrics(
            connectId: connectId,
            state: circuit.state,
            consecutiveFailures: circuit.consecutiveFailures,
            timeSinceLastTransition: Date().timeIntervalSince(circuit.lastStateTransition),
            timeSinceLastFailure: circuit.lastFailureTime.map { Date().timeIntervalSince($0) }
        )
    }
}

// MARK: - Configuration

/// Configuration for circuit breaker behavior
/// Migrated from: CircuitBreakerConfiguration.cs
public struct CircuitBreakerConfiguration {

    /// Number of consecutive failures before opening circuit
    public let failureThreshold: Int

    /// Number of consecutive successes required to close circuit from half-open
    public let successThreshold: Int

    /// Duration to keep circuit open before attempting half-open (in seconds)
    public let openStateDuration: TimeInterval

    /// Whether to use per-connection circuit breakers
    public let usePerConnectionCircuits: Bool

    public init(
        failureThreshold: Int = 5,
        successThreshold: Int = 2,
        openStateDuration: TimeInterval = 30.0,
        usePerConnectionCircuits: Bool = true
    ) {
        self.failureThreshold = failureThreshold
        self.successThreshold = successThreshold
        self.openStateDuration = openStateDuration
        self.usePerConnectionCircuits = usePerConnectionCircuits
    }

    // MARK: - Presets

    /// Default configuration (5 failures, 2 successes, 30s open duration)
    public static let `default` = CircuitBreakerConfiguration()

    /// Aggressive configuration (3 failures, 1 success, 15s open duration)
    public static let aggressive = CircuitBreakerConfiguration(
        failureThreshold: 3,
        successThreshold: 1,
        openStateDuration: 15.0
    )

    /// Conservative configuration (10 failures, 3 successes, 60s open duration)
    public static let conservative = CircuitBreakerConfiguration(
        failureThreshold: 10,
        successThreshold: 3,
        openStateDuration: 60.0
    )

    /// Disabled (very high threshold)
    public static let disabled = CircuitBreakerConfiguration(
        failureThreshold: Int.max,
        successThreshold: 1,
        openStateDuration: 1.0,
        usePerConnectionCircuits: false
    )
}

// MARK: - Metrics

/// Circuit breaker metrics
public struct CircuitBreakerMetrics {
    public let state: CircuitBreaker.State
    public let consecutiveFailures: Int
    public let consecutiveSuccesses: Int
    public let totalFailures: Int
    public let totalSuccesses: Int
    public let timeSinceLastTransition: TimeInterval
}

/// Per-connection circuit breaker metrics
public struct ConnectionCircuitMetrics {
    public let connectId: UInt32
    public let state: CircuitBreaker.State
    public let consecutiveFailures: Int
    public let timeSinceLastTransition: TimeInterval
    public let timeSinceLastFailure: TimeInterval?
}
