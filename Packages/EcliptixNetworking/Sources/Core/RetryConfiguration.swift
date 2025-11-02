import Foundation

public struct RetryConfiguration: Sendable {

    public let maxRetries: Int

    public let initialDelay: TimeInterval

    public let maxDelay: TimeInterval

    public let timeoutPerAttempt: TimeInterval

    public let useExponentialBackoff: Bool

    public let useJitter: Bool

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

    public static let `default` = RetryConfiguration()

    public static let aggressive = RetryConfiguration(
        maxRetries: 5,
        initialDelay: 0.5,
        maxDelay: 60.0,
        timeoutPerAttempt: 45.0
    )

    public static let conservative = RetryConfiguration(
        maxRetries: 2,
        initialDelay: 2.0,
        maxDelay: 15.0,
        timeoutPerAttempt: 20.0
    )

    public static let none = RetryConfiguration(
        maxRetries: 0,
        initialDelay: 0,
        maxDelay: 0,
        timeoutPerAttempt: 30.0,
        useExponentialBackoff: false,
        useJitter: false
    )
}

public enum NetworkError: LocalizedError {
    case timeout(TimeInterval)
    case cancelled
    case retriesExhausted(String)
    case connectionFailed(String)
    case invalidResponse
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "Operation timed out after \(String(format: "%.1f", seconds))s"
        case .cancelled:
            return "Operation was cancelled"
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
