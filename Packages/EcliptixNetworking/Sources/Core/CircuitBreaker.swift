import EcliptixCore
import Foundation

@MainActor
public final class CircuitBreaker {

    public enum State: String {
        case closed
        case open
        case halfOpen
    }

    private(set) var state: State = .closed

    private let configuration: CircuitBreakerConfiguration

    private var consecutiveFailures: Int = 0

    private var consecutiveSuccesses: Int = 0

    private var lastStateTransition: Date = Date()

    private var totalFailures: Int = 0

    private var totalSuccesses: Int = 0

    private var connectionCircuits: [UInt32: ConnectionCircuitState] = [:]
    private let circuitLock = NSLock()

    @MainActor
    private class ConnectionCircuitState {
        let connectId: UInt32
        var state: State
        var consecutiveFailures: Int
        var lastStateTransition: Date
        var lastFailureTime: Date?
        private let stateLock = NSLock()

        init(connectId: UInt32) {
            self.connectId = connectId
            self.state = .closed
            self.consecutiveFailures = 0
            self.lastStateTransition = Date()
        }

        func atomicUpdate(_ update: (ConnectionCircuitState) -> Void) {
            stateLock.lock()
            defer { stateLock.unlock() }
            update(self)
        }

        func atomicRead<T>(_ read: (ConnectionCircuitState) -> T) -> T {
            stateLock.lock()
            defer { stateLock.unlock() }
            return read(self)
        }
    }

    public init(configuration: CircuitBreakerConfiguration = .default) {
        self.configuration = configuration
    }

    public func execute<T>(
        connectId: UInt32? = nil,
        operationName: String,
        operation: @escaping () async throws -> Result<T, NetworkFailure>
    ) async -> Result<T, NetworkFailure> {

        if let connectId = connectId {
            if isCircuitOpen(connectId: connectId) {
                Log.warning("[CircuitBreaker] [ERROR] Circuit OPEN for connection \(connectId) - failing fast: \(operationName)")
                return .failure(NetworkFailure(
                    type: .dataCenterNotResponding,
                    message: "Circuit breaker is open - service temporarily unavailable"
                ))
            }
        } else {
            if state == .open && !shouldAttemptReset() {
                Log.warning("[CircuitBreaker] [ERROR] Circuit OPEN globally - failing fast: \(operationName)")
                return .failure(NetworkFailure(
                    type: .dataCenterNotResponding,
                    message: "Circuit breaker is open - service temporarily unavailable"
                ))
            }
        }

        do {
            let result = try await operation()

            switch result {
            case .success:

                if let connectId = connectId {
                    recordSuccess(connectId: connectId)
                } else {
                    recordSuccess()
                }
                return result

            case .failure(let error):

                if let connectId = connectId {
                    recordFailure(connectId: connectId, error: error)
                } else {
                    recordFailure(error: error)
                }
                return result
            }

        } catch {

            let failure = NetworkFailure(
                type: .unknown,
                message: "Circuit breaker caught unexpected error: \(error.localizedDescription)"
            )

            if let connectId = connectId {
                recordFailure(connectId: connectId, error: failure)
            } else {
                recordFailure(error: failure)
            }

            return .failure(failure)
        }
    }

    private func recordSuccess() {
        totalSuccesses += 1

        switch state {
        case .halfOpen:

            consecutiveSuccesses += 1

            if consecutiveSuccesses >= configuration.successThreshold {

                transitionTo(.closed)
                consecutiveFailures = 0
                consecutiveSuccesses = 0
                Log.info("[CircuitBreaker] [OK] Circuit CLOSED - service recovered (\(consecutiveSuccesses) successes)")
            }

        case .closed:

            if consecutiveFailures > 0 {
                consecutiveFailures = 0
            }

        case .open:

            transitionTo(.halfOpen)
        }
    }

    private func recordFailure(error: NetworkFailure) {
        totalFailures += 1

        guard error.shouldRetry else {
            return
        }

        consecutiveFailures += 1

        switch state {
        case .closed:
            if consecutiveFailures >= configuration.failureThreshold {
                transitionTo(.open)
                Log.warning("[CircuitBreaker] [ERROR] Circuit OPEN - failure threshold exceeded (\(consecutiveFailures) failures)")
            }

        case .halfOpen:

            transitionTo(.open)
            consecutiveSuccesses = 0
            Log.warning("[CircuitBreaker] [ERROR] Circuit RE-OPENED - service still failing")

        case .open:

            break
        }
    }

    private func transitionTo(_ newState: State) {
        guard state != newState else { return }

        let oldState = state
        state = newState
        lastStateTransition = Date()

        Log.info("[CircuitBreaker]  State transition: \(oldState.rawValue) → \(newState.rawValue)")
    }

    private func shouldAttemptReset() -> Bool {
        guard state == .open else { return false }

        let timeSinceOpen = Date().timeIntervalSince(lastStateTransition)
        if timeSinceOpen >= configuration.openStateDuration {

            transitionTo(.halfOpen)
            return true
        }

        return false
    }

    private func recordSuccess(connectId: UInt32) {
        circuitLock.lock()
        defer { circuitLock.unlock() }

        guard let circuit = connectionCircuits[connectId] else {
            return
        }

        circuit.atomicUpdate { state in
            if state.state == .halfOpen {
                state.state = .closed
                state.consecutiveFailures = 0
                state.lastStateTransition = Date()
                Log.info("[CircuitBreaker] [OK] Circuit CLOSED for connection \(connectId)")
            } else if state.state == .closed {
                state.consecutiveFailures = 0
            }
        }
    }

    private func recordFailure(connectId: UInt32, error: NetworkFailure) {
        guard error.shouldRetry else {
            return
        }

        circuitLock.lock()
        let circuit = connectionCircuits[connectId] ?? ConnectionCircuitState(connectId: connectId)
        if connectionCircuits[connectId] == nil {
            connectionCircuits[connectId] = circuit
        }
        circuitLock.unlock()

        circuit.atomicUpdate { state in
            state.consecutiveFailures += 1
            state.lastFailureTime = Date()
        }

        let shouldOpen = circuit.atomicRead { state in
            state.state == .closed && state.consecutiveFailures >= configuration.failureThreshold
        }

        if shouldOpen {
            circuit.atomicUpdate { state in
                state.state = .open
                state.lastStateTransition = Date()
            }
            let failures = circuit.atomicRead { $0.consecutiveFailures }
            Log.warning("[CircuitBreaker] [ERROR] Circuit OPEN for connection \(connectId) - \(failures) failures")
        } else {
            let isHalfOpen = circuit.atomicRead { $0.state == .halfOpen }
            if isHalfOpen {
                circuit.atomicUpdate { state in
                    state.state = .open
                    state.lastStateTransition = Date()
                }
                Log.warning("[CircuitBreaker] [ERROR] Circuit RE-OPENED for connection \(connectId)")
            }
        }
    }

    private func isCircuitOpen(connectId: UInt32) -> Bool {
        guard let circuit = connectionCircuits[connectId] else {
            return false
        }

        if circuit.state == .open {
            let timeSinceOpen = Date().timeIntervalSince(circuit.lastStateTransition)
            if timeSinceOpen >= configuration.openStateDuration {

                circuit.state = .halfOpen
                circuit.lastStateTransition = Date()
                Log.info("[CircuitBreaker]  Circuit HALF-OPEN for connection \(connectId) - testing recovery")
                return false
            }
            return true
        }

        return false
    }

    public func trip() {
        transitionTo(.open)
        Log.warning("[CircuitBreaker] [ERROR] Circuit manually TRIPPED")
    }

    public func reset() {
        transitionTo(.closed)
        consecutiveFailures = 0
        consecutiveSuccesses = 0
        totalFailures = 0
        totalSuccesses = 0

        connectionCircuits.removeAll()

        Log.info("[CircuitBreaker] [OK] Circuit manually RESET")
    }

    public func resetConnection(_ connectId: UInt32) {
        if let circuit = connectionCircuits[connectId] {
            circuit.state = .closed
            circuit.consecutiveFailures = 0
            circuit.lastStateTransition = Date()
            Log.info("[CircuitBreaker] [OK] Circuit RESET for connection \(connectId)")
        }
    }

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

    public func getConnectionMetrics(connectId: UInt32) -> ConnectionCircuitMetrics? {
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

public struct CircuitBreakerConfiguration: Sendable {

    public let failureThreshold: Int

    public let successThreshold: Int

    public let openStateDuration: TimeInterval

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

    public static let `default` = CircuitBreakerConfiguration()

    public static let aggressive = CircuitBreakerConfiguration(
        failureThreshold: 3,
        successThreshold: 1,
        openStateDuration: 15.0
    )

    public static let conservative = CircuitBreakerConfiguration(
        failureThreshold: 10,
        successThreshold: 3,
        openStateDuration: 60.0
    )

    public static let disabled = CircuitBreakerConfiguration(
        failureThreshold: Int.max,
        successThreshold: 1,
        openStateDuration: 1.0,
        usePerConnectionCircuits: false
    )
}

public struct CircuitBreakerMetrics {
    public let state: CircuitBreaker.State
    public let consecutiveFailures: Int
    public let consecutiveSuccesses: Int
    public let totalFailures: Int
    public let totalSuccesses: Int
    public let timeSinceLastTransition: TimeInterval
}

public struct ConnectionCircuitMetrics {
    public let connectId: UInt32
    public let state: CircuitBreaker.State
    public let consecutiveFailures: Int
    public let timeSinceLastTransition: TimeInterval
    public let timeSinceLastFailure: TimeInterval?
}
