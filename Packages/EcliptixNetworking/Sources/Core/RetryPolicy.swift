import EcliptixCore
import Foundation

public final class RetryPolicy {
    private let configuration: RetryConfiguration
    public init(configuration: RetryConfiguration = .default) {
        self.configuration = configuration
    }

    public func execute<T: Sendable>(
        operationName: String,
        operation: @escaping @Sendable (Int) async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...configuration.maxRetries {
            do {
                Log.debug("[\(operationName)] Attempt \(attempt)/\(configuration.maxRetries)")

                let result = try await withTimeout(seconds: configuration.timeoutPerAttempt) {
                    try await operation(attempt)
                }

                if attempt > 1 {
                    Log.info("[\(operationName)] Succeeded on attempt \(attempt)")
                }

                return result

            } catch {
                lastError = error
                Log.warning("[\(operationName)] Attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt >= configuration.maxRetries {
                    break
                }

                let delay = calculateDelay(for: attempt)
                Log.debug("[\(operationName)] Retrying after \(String(format: "%.2f", delay))s...")

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        Log.error("[\(operationName)] All \(configuration.maxRetries) attempts failed")
        throw lastError ?? NetworkError.retriesExhausted(operationName)
    }

    private func calculateDelay(for attempt: Int) -> TimeInterval {
        guard configuration.useExponentialBackoff else {
            return configuration.initialDelay
        }

        let exponentialDelay = configuration.initialDelay * pow(2.0, Double(attempt - 1))

        let jitterFactor = Double.random(in: 0.8...1.2)
        let delayWithJitter = exponentialDelay * jitterFactor

        return min(delayWithJitter, configuration.maxDelay)
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NetworkError.timeout(seconds)
            }

            guard let result = try await group.next() else {
                throw NetworkError.cancelled
            }

            group.cancelAll()

            return result
        }
    }
}
