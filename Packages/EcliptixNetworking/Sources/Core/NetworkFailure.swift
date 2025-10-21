import Foundation

// MARK: - Network Failure Type
/// Classification of network failures
/// Migrated from: Ecliptix.Utilities/Failures/Network/NetworkFailureType.cs
public enum NetworkFailureType: String, Codable {
    case dataCenterNotResponding
    case authenticationRequired
    case sessionExpired
    case invalidRequest
    case serverError
    case timeout
    case networkUnavailable
    case operationCancelled
    case rateLimited
    case unknown
}

// MARK: - Network Failure
/// Represents a network operation failure
/// Migrated from: Ecliptix.Utilities/Failures/Network/NetworkFailure.cs
public struct NetworkFailure: LocalizedError, Equatable {

    // MARK: - Properties
    public let type: NetworkFailureType
    public let message: String
    public let underlyingError: String?
    public let retryAfter: TimeInterval?

    // MARK: - Initialization
    public init(
        type: NetworkFailureType,
        message: String,
        underlyingError: Error? = nil,
        retryAfter: TimeInterval? = nil
    ) {
        self.type = type
        self.message = message
        self.underlyingError = underlyingError?.localizedDescription
        self.retryAfter = retryAfter
    }

    // MARK: - Factory Methods

    public static func dataCenterNotResponding(_ message: String) -> NetworkFailure {
        NetworkFailure(type: .dataCenterNotResponding, message: message)
    }

    public static func authenticationRequired(_ message: String) -> NetworkFailure {
        NetworkFailure(type: .authenticationRequired, message: message)
    }

    public static func sessionExpired(_ message: String) -> NetworkFailure {
        NetworkFailure(type: .sessionExpired, message: message)
    }

    public static func invalidRequest(_ message: String) -> NetworkFailure {
        NetworkFailure(type: .invalidRequest, message: message)
    }

    public static func serverError(_ message: String, error: Error? = nil) -> NetworkFailure {
        NetworkFailure(type: .serverError, message: message, underlyingError: error)
    }

    public static func timeout(_ message: String) -> NetworkFailure {
        NetworkFailure(type: .timeout, message: message)
    }

    public static func networkUnavailable(_ message: String) -> NetworkFailure {
        NetworkFailure(type: .networkUnavailable, message: message)
    }

    public static func operationCancelled(_ message: String) -> NetworkFailure {
        NetworkFailure(type: .operationCancelled, message: message)
    }

    public static func rateLimited(_ message: String, retryAfter: TimeInterval?) -> NetworkFailure {
        NetworkFailure(type: .rateLimited, message: message, retryAfter: retryAfter)
    }

    public static func unknown(_ message: String, error: Error? = nil) -> NetworkFailure {
        NetworkFailure(type: .unknown, message: message, underlyingError: error)
    }

    // MARK: - LocalizedError
    public var errorDescription: String? {
        return message
    }

    // MARK: - Equatable
    public static func == (lhs: NetworkFailure, rhs: NetworkFailure) -> Bool {
        return lhs.type == rhs.type &&
               lhs.message == rhs.message &&
               lhs.underlyingError == rhs.underlyingError &&
               lhs.retryAfter == rhs.retryAfter
    }
}

// MARK: - User-Facing Error
/// User-friendly error messages
/// Migrated from: Ecliptix.Utilities/Failures/Network/UserFacingError.cs
public struct UserFacingError {
    public let title: String
    public let message: String
    public let canRetry: Bool

    public init(title: String, message: String, canRetry: Bool = false) {
        self.title = title
        self.message = message
        self.canRetry = canRetry
    }

    /// Converts a NetworkFailure to a user-facing error
    public static func from(_ failure: NetworkFailure) -> UserFacingError {
        switch failure.type {
        case .dataCenterNotResponding:
            return UserFacingError(
                title: "Connection Issue",
                message: "Unable to reach the server. Please check your internet connection and try again.",
                canRetry: true
            )

        case .authenticationRequired:
            return UserFacingError(
                title: "Authentication Required",
                message: "Please sign in to continue.",
                canRetry: false
            )

        case .sessionExpired:
            return UserFacingError(
                title: "Session Expired",
                message: "Your session has expired. Please sign in again.",
                canRetry: false
            )

        case .invalidRequest:
            return UserFacingError(
                title: "Invalid Request",
                message: "The request was not valid. Please try again.",
                canRetry: false
            )

        case .serverError:
            return UserFacingError(
                title: "Server Error",
                message: "The server encountered an error. Please try again later.",
                canRetry: true
            )

        case .timeout:
            return UserFacingError(
                title: "Request Timeout",
                message: "The request took too long. Please check your connection and try again.",
                canRetry: true
            )

        case .networkUnavailable:
            return UserFacingError(
                title: "No Internet Connection",
                message: "Please check your internet connection and try again.",
                canRetry: true
            )

        case .operationCancelled:
            return UserFacingError(
                title: "Operation Cancelled",
                message: "The operation was cancelled.",
                canRetry: false
            )

        case .rateLimited:
            let retryMessage = failure.retryAfter != nil
                ? "Please wait \(Int(failure.retryAfter!)) seconds before trying again."
                : "Please try again in a few moments."
            return UserFacingError(
                title: "Too Many Requests",
                message: retryMessage,
                canRetry: true
            )

        case .unknown:
            return UserFacingError(
                title: "Unknown Error",
                message: "An unexpected error occurred. Please try again.",
                canRetry: true
            )
        }
    }
}
