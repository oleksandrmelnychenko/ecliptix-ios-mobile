import Combine
import Foundation

public enum RetryState: Sendable, Equatable {
    case idle
    case retrying(attempt: Int)
    case exhausted(totalAttempts: Int)
    case succeeded
}

public actor RetryStrategy {

    private let configuration: RetryStrategyConfiguration
    private let connectivityService: ConnectivityService

    private var currentAttempt: Int = 0
    private var isExhausted: Bool = false
    private var lastFailure: NetworkFailure?

    nonisolated(unsafe) private let retryStateSubject = CurrentValueSubject<RetryState, Never>(.idle)
    public nonisolated var retryStatePublisher: AnyPublisher<RetryState, Never> {
        retryStateSubject.eraseToAnyPublisher()
    }

    public init(
        configuration: RetryStrategyConfiguration = .default,
        connectivityService: ConnectivityService
    ) {
        self.configuration = configuration
        self.connectivityService = connectivityService

        Log.info("[RetryStrategy] Initialized with config: \(configuration)")
    }

    public func execute<T>(
        connectId: UInt32? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {

        resetOnSuccess()

        while true {
            if isRetryExhausted() {
                Log.error("[RetryStrategy]  Retry exhausted globally")
                throw lastFailure ?? .unknown("Retry exhausted")
            }

            let currentAttemptNumber = getCurrentAttempt()
            guard configuration.canRetry(attempt: currentAttemptNumber) else {
                markExhausted(connectId: connectId)
                throw lastFailure ?? .unknown("Max retries exceeded")
            }

            if currentAttemptNumber > 0 {
                updateRetryState(.retrying(attempt: currentAttemptNumber))
            }

            do {

                let result = try await operation()

                onSuccess()
                return result

            } catch let error as NetworkFailure {
                try await handleFailure(
                    error,
                    attempt: currentAttemptNumber,
                    connectId: connectId
                )

                incrementAttempt()

            } catch {

                Log.error("[RetryStrategy] [FAILED] Non-network error, not retrying: \(error)")
                throw NetworkFailure.unknown(error.localizedDescription, underlyingError: error)
            }
        }
    }

    public func reset() {
        currentAttempt = 0
        isExhausted = false
        lastFailure = nil
        retryStateSubject.send(.idle)

        Log.info("[RetryStrategy]  State reset (manual retry)")
    }

    public func isRetryExhausted() -> Bool {
        return isExhausted
    }

    private func resetOnSuccess() {
        if retryStateSubject.value == .succeeded || retryStateSubject.value == .idle {
            currentAttempt = 0
            lastFailure = nil
            retryStateSubject.send(.idle)
        }
    }

    private func getCurrentAttempt() -> Int {
        return currentAttempt
    }

    private func incrementAttempt() {
        currentAttempt += 1
    }

    private func updateRetryState(_ state: RetryState) {
        retryStateSubject.send(state)
    }

    private func handleFailure(
        _ failure: NetworkFailure,
        attempt: Int,
        connectId: UInt32?
    ) async throws {
        lastFailure = failure

        Log.warning("[RetryStrategy] [WARNING] Attempt \(attempt + 1)/\(configuration.maxRetries) failed: \(failure.localizedDescription)")

        if isNonRetryableFailure(failure) {
            Log.error("[RetryStrategy]  Non-retryable failure detected")
            markExhausted(connectId: connectId)
            throw failure
        }

        let delay = configuration.calculateDelay(for: attempt)

        await connectivityService.publish(
            .recovering(
                failure: failure,
                connectId: connectId,
                retryAttempt: attempt + 1,
                backoff: delay
            )
        )

        Log.debug("[RetryStrategy] ⏳ Backing off for \(String(format: "%.1fs", delay))...")
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        Log.debug("[RetryStrategy]  Retrying attempt \(attempt + 2)...")
    }

    private func markExhausted(connectId: UInt32?) {
        isExhausted = true
        let totalAttempts = currentAttempt
        let failure = lastFailure ?? .unknown("Unknown failure")

        retryStateSubject.send(.exhausted(totalAttempts: totalAttempts))

        Task { [connectivityService] in
            connectivityService.notifyRetriesExhausted(
                failure: failure,
                connectId: connectId,
                retries: totalAttempts
            )
        }

        Log.error("[RetryStrategy]  Retries EXHAUSTED after \(totalAttempts) attempts")
    }

    private func onSuccess() {
        currentAttempt = 0
        isExhausted = false
        lastFailure = nil

        retryStateSubject.send(.succeeded)
        Log.info("[RetryStrategy] [OK] Operation succeeded")
    }

    private func isNonRetryableFailure(_ failure: NetworkFailure) -> Bool {
        switch failure.type {
        case .serviceUnavailable:
            return true
        case .authenticationFailed,
             .unauthorized,
             .forbidden:
            return true
        case .clientError:
            return true
        case .operationCancelled:
            return true
        default:
            return false
        }
    }
}

extension RetryStrategy {

    public func executeWithResult<T>(
        connectId: UInt32? = nil,
        operation: @escaping () async throws -> T
    ) async -> Result<T, NetworkFailure> {
        do {
            let value = try await execute(connectId: connectId, operation: operation)
            return .success(value)
        } catch let error as NetworkFailure {
            return .failure(error)
        } catch {
            return .failure(.unknown(error.localizedDescription, underlyingError: error))
        }
    }

    public var isRetrying: Bool {
        if case .retrying = retryStateSubject.value {
            return true
        }
        return false
    }

    public var currentRetryAttempt: Int? {
        if case .retrying(let attempt) = retryStateSubject.value {
            return attempt
        }
        return nil
    }
}

extension RetryStrategy: CustomStringConvertible {
    public nonisolated var description: String {
        return """
        RetryStrategy(
          state: \(retryStateSubject.value),
          config: \(configuration)
        )
        """
    }
}

extension RetryState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .retrying(let attempt):
            return "Retrying (attempt \(attempt))"
        case .exhausted(let totalAttempts):
            return "Exhausted (tried \(totalAttempts) times)"
        case .succeeded:
            return "Succeeded"
        }
    }
}
