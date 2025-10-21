import Foundation

// MARK: - Retry Configuration
/// Configuration for retry behavior
/// Migrated from: Ecliptix.Core/Services/Network/Resilience/RetryConfiguration.cs
public struct RetryConfiguration {

    // MARK: - Properties

    /// Maximum number of retry attempts
    public let maxRetries: Int

    /// Initial delay before first retry (in seconds)
    public let initialDelay: TimeInterval

    /// Maximum delay between retries (in seconds)
    public let maxDelay: TimeInterval

    /// Timeout for each individual retry attempt (in seconds)
    public let timeoutPerAttempt: TimeInterval

    /// Whether to use exponential backoff
    public let useExponentialBackoff: Bool

    /// Whether to add jitter to retry delays
    public let useJitter: Bool

    // MARK: - Initialization

    public init(
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        timeoutPerAttempt: TimeInterval = 30.0,
        useExponentialBackoff: Bool = true,
        useJitter: Bool = true
    ) {
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.timeoutPerAttempt = timeoutPerAttempt
        self.useExponentialBackoff = useExponentialBackoff
        self.useJitter = useJitter
    }

    // MARK: - Presets

    /// Default configuration (3 retries, 1s initial delay, 30s max delay)
    public static let `default` = RetryConfiguration()

    /// Aggressive configuration (5 retries, 0.5s initial delay, 60s max delay)
    public static let aggressive = RetryConfiguration(
        maxRetries: 5,
        initialDelay: 0.5,
        maxDelay: 60.0,
        timeoutPerAttempt: 45.0
    )

    /// Conservative configuration (2 retries, 2s initial delay, 15s max delay)
    public static let conservative = RetryConfiguration(
        maxRetries: 2,
        initialDelay: 2.0,
        maxDelay: 15.0,
        timeoutPerAttempt: 20.0
    )

    /// No retry configuration (0 retries)
    public static let none = RetryConfiguration(
        maxRetries: 0,
        initialDelay: 0,
        maxDelay: 0,
        timeoutPerAttempt: 30.0,
        useExponentialBackoff: false,
        useJitter: false
    )
}

// MARK: - Network Error
/// Network-related errors
enum NetworkError: LocalizedError {
    case timeout(TimeInterval)
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "Operation timed out after \(String(format: "%.1f", seconds))s"
        case .cancelled:
            return "Operation was cancelled"
        case .unknown(let message):
            return "Network error: \(message)"
        }
    }
}
