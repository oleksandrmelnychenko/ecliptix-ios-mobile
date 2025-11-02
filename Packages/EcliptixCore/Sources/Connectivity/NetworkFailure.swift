import Foundation

public struct NetworkFailure: Error, Sendable {

    public let type: FailureType

    public let message: String

    public let underlyingError: Error?

    public let retryInfo: RetryInfo?

    public init(
        type: FailureType,
        message: String,
        underlyingError: Error? = nil,
        retryInfo: RetryInfo? = nil
    ) {
        self.type = type
        self.message = message
        self.underlyingError = underlyingError
        self.retryInfo = retryInfo
    }

    public enum FailureType: Sendable {
        case networkUnavailable
        case connectionTimeout
        case serverNotResponding
        case serverError
        case clientError
        case authenticationFailed
        case unauthorized
        case forbidden
        case notFound
        case conflict
        case tooManyRequests
        case serviceUnavailable
        case gatewayTimeout
        case invalidResponse
        case operationCancelled
        case protocolStateMismatch
        case handshakeFailed
        case connectionFailed
        case unavailable
        case timeout
        case unknown
    }

    public struct RetryInfo: Sendable {
        public let currentAttempt: Int
        public let maxAttempts: Int
        public let nextRetryDelay: TimeInterval
        public let backoffStrategy: BackoffStrategy

        public init(
            currentAttempt: Int,
            maxAttempts: Int,
            nextRetryDelay: TimeInterval,
            backoffStrategy: BackoffStrategy
        ) {
            self.currentAttempt = currentAttempt
            self.maxAttempts = maxAttempts
            self.nextRetryDelay = nextRetryDelay
            self.backoffStrategy = backoffStrategy
        }

        public enum BackoffStrategy: Sendable {
            case exponential
            case linear
            case fixed
        }
    }
}

extension NetworkFailure: CustomStringConvertible {
    public var description: String {
        var desc = "NetworkFailure(\(type)): \(message)"
        if let retry = retryInfo {
            desc += " [Retry \(retry.currentAttempt)/\(retry.maxAttempts)]"
        }
        if let error = underlyingError {
            desc += " Underlying: \(error)"
        }
        return desc
    }
}

extension NetworkFailure {
    public static func networkUnavailable(
        _ message: String = "Network connection unavailable"
    ) -> NetworkFailure {
        NetworkFailure(type: .networkUnavailable, message: message)
    }

    public static func timeout(
        _ message: String = "Connection timeout"
    ) -> NetworkFailure {
        NetworkFailure(type: .connectionTimeout, message: message)
    }

    public static func serverError(
        _ message: String = "Server error occurred"
    ) -> NetworkFailure {
        NetworkFailure(type: .serverError, message: message)
    }

    public static func cancelled(
        _ message: String = "Operation cancelled"
    ) -> NetworkFailure {
        NetworkFailure(type: .operationCancelled, message: message)
    }

    public static func dataCenterNotResponding(
        _ message: String = "Data center not responding"
    ) -> NetworkFailure {
        NetworkFailure(type: .serverNotResponding, message: message)
    }

    public static func unknown(
        _ message: String = "Unknown error occurred",
        underlyingError: Error? = nil
    ) -> NetworkFailure {
        NetworkFailure(
            type: .unknown,
            message: message,
            underlyingError: underlyingError
        )
    }

    public var shouldRetry: Bool {
        switch type {
        case .networkUnavailable, .connectionTimeout, .serverNotResponding,
             .serverError, .tooManyRequests, .serviceUnavailable, .gatewayTimeout,
             .connectionFailed, .unavailable, .timeout, .unknown:
            return true
        case .protocolStateMismatch, .handshakeFailed:
            return true
        case .clientError, .authenticationFailed, .unauthorized, .forbidden,
             .notFound, .conflict, .invalidResponse, .operationCancelled:
            return false
        }
    }
}
