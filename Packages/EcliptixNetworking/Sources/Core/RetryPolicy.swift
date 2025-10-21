import Foundation
import EcliptixCore

// MARK: - Retry Configuration
/// Configuration for retry behavior
/// Migrated from: Ecliptix.Core/Services/Network/Resilience/RetryStrategyConfiguration.cs
public struct RetryConfiguration {
    public let maxRetries: Int
    public let initialDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let useExponentialBackoff: Bool
    public let timeoutPerAttempt: TimeInterval

    public static let `default` = RetryConfiguration(
        maxRetries: 3,
        initialDelay: 1.0,  // 1 second
        maxDelay: 30.0,     // 30 seconds
        useExponentialBackoff: true,
        timeoutPerAttempt: 30.0
    )

    public init(
        maxRetries: Int,
        initialDelay: TimeInterval,
        maxDelay: TimeInterval,
        useExponentialBackoff: Bool = true,
        timeoutPerAttempt: TimeInterval = 30.0
    ) {
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.useExponentialBackoff = useExponentialBackoff
        self.timeoutPerAttempt = timeoutPerAttempt
    }
}

// MARK: - Retry Policy
/// Implements exponential backoff retry logic
/// Migrated from: Ecliptix.Core/Services/Network/Resilience/RetryStrategy.cs (simplified)
public final class RetryPolicy {

    // MARK: - Properties
    private let configuration: RetryConfiguration

    // MARK: - Initialization
    public init(configuration: RetryConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Execute with Retry
    /// Executes an async operation with retry logic
    /// Migrated from: ExecuteRpcOperationAsync()
    public func execute<T>(
        operationName: String,
        operation: @escaping (Int) async throws -> T
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

                // Don't retry if it's the last attempt
                if attempt >= configuration.maxRetries {
                    break
                }

                // Calculate delay
                let delay = calculateDelay(for: attempt)
                Log.debug("[\(operationName)] Retrying after \(String(format: "%.2f", delay))s...")

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // All retries exhausted
        Log.error("[\(operationName)] All \(configuration.maxRetries) attempts failed")
        throw lastError ?? NetworkError.retriesExhausted(operationName)
    }

    // MARK: - Execute with Result
    /// Executes an operation returning Result type with retry
    public func executeWithResult<T, E: Error>(
        operationName: String,
        operation: @escaping (Int) async -> Result<T, E>
    ) async -> Result<T, E> {
        var lastError: E?

        for attempt in 1...configuration.maxRetries {
            Log.debug("[\(operationName)] Attempt \(attempt)/\(configuration.maxRetries)")

            let result = await operation(attempt)

            switch result {
            case .success(let value):
                if attempt > 1 {
                    Log.info("[\(operationName)] Succeeded on attempt \(attempt)")
                }
                return .success(value)

            case .failure(let error):
                lastError = error
                Log.warning("[\(operationName)] Attempt \(attempt) failed: \(error.localizedDescription)")

                // Don't retry if it's the last attempt
                if attempt >= configuration.maxRetries {
                    break
                }

                // Calculate delay
                let delay = calculateDelay(for: attempt)
                Log.debug("[\(operationName)] Retrying after \(String(format: "%.2f", delay))s...")

                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    // Sleep was cancelled
                    return .failure(error as! E)
                }
            }
        }

        // All retries exhausted
        Log.error("[\(operationName)] All \(configuration.maxRetries) attempts failed")
        if let lastError = lastError {
            return .failure(lastError)
        }

        // This shouldn't happen, but provide a fallback
        return .failure(NetworkError.retriesExhausted(operationName) as! E)
    }

    // MARK: - Calculate Delay
    /// Calculates retry delay using exponential backoff
    /// Migrated from: GetOrCreateRetryDelays() / Backoff.DecorrelatedJitterBackoffV2()
    private func calculateDelay(for attempt: Int) -> TimeInterval {
        guard configuration.useExponentialBackoff else {
            return configuration.initialDelay
        }

        // Exponential backoff: initialDelay * (2 ^ (attempt - 1))
        let exponentialDelay = configuration.initialDelay * pow(2.0, Double(attempt - 1))

        // Add jitter (random ±20%)
        let jitterFactor = Double.random(in: 0.8...1.2)
        let delayWithJitter = exponentialDelay * jitterFactor

        // Cap at max delay
        return min(delayWithJitter, configuration.maxDelay)
    }

    // MARK: - With Timeout
    /// Executes an operation with a timeout
    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Start the operation
            group.addTask {
                try await operation()
            }

            // Start the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NetworkError.timeout(seconds)
            }

            // Return the first one to complete
            let result = try await group.next()!

            // Cancel the other task
            group.cancelAll()

            return result
        }
    }
}

// MARK: - Network Error
/// Network-related errors
public enum NetworkError: LocalizedError {
    case timeout(TimeInterval)
    case retriesExhausted(String)
    case connectionFailed(String)
    case invalidResponse
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "Operation timed out after \(seconds) seconds"
        case .retriesExhausted(let operation):
            return "All retry attempts exhausted for operation: \(operation)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .invalidResponse:
            return "Invalid response from server"
        case .unknown(let message):
            return "Network error: \(message)"
        }
    }
}
