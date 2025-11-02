import Foundation

public enum NetworkFailureType: String, Codable, Sendable {

    case dataCenterNotResponding
    case timeout
    case connectionFailed
    case unavailable
    case networkUnavailable
    case operationCancelled
    case cancelled

    case authenticationRequired
    case unauthenticated
    case permissionDenied
    case sessionExpired

    case protocolStateMismatch
    case handshakeFailed
    case encryptionFailed
    case decryptionFailed

    case invalidRequest
    case invalidArgument
    case notFound
    case alreadyExists
    case failedPrecondition

    case serverError
    case serialization

    case rateLimited

    case unknown
}

public struct UserFacingError: Codable, Equatable, Sendable {
    public let errorCode: String
    public let title: String
    public let message: String
    public let localizedKey: String?
    public let canRetry: Bool

    public init(
        errorCode: String,
        title: String = "",
        message: String,
        localizedKey: String? = nil,
        canRetry: Bool = false
    ) {
        self.errorCode = errorCode
        self.title = title
        self.message = message
        self.localizedKey = localizedKey
        self.canRetry = canRetry
    }
}

public struct NetworkFailure: LocalizedError, Equatable, Sendable {
    public let type: NetworkFailureType
    public let message: String
    public let underlyingError: String?
    public let retryAfter: TimeInterval?
    public let userError: UserFacingError?
    public let isRetryable: Bool
    public let metadata: [String: String]
    public init(
        type: NetworkFailureType,
        message: String,
        underlyingError: Error? = nil,
        retryAfter: TimeInterval? = nil,
        userError: UserFacingError? = nil,
        isRetryable: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.type = type
        self.message = message
        self.underlyingError = underlyingError?.localizedDescription
        self.retryAfter = retryAfter
        self.userError = userError
        self.isRetryable = isRetryable
        self.metadata = metadata
    }

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

    public var shouldRetry: Bool {

        if isRetryable {
            return true
        }

        switch type {
        case .dataCenterNotResponding, .serverError, .timeout, .networkUnavailable, .rateLimited, .unknown:
            return true
        case .connectionFailed, .unavailable:
            return true
        case .protocolStateMismatch, .handshakeFailed:
            return true
        case .encryptionFailed, .decryptionFailed:
            return false
        case .authenticationRequired, .unauthenticated, .permissionDenied, .sessionExpired:
            return false
        case .invalidRequest, .invalidArgument, .notFound, .alreadyExists, .failedPrecondition:
            return false
        case .operationCancelled, .cancelled:
            return false
        case .serialization:
            return true
        }
    }
    public var errorDescription: String? {
        return message
    }
    public static func == (lhs: NetworkFailure, rhs: NetworkFailure) -> Bool {
        return lhs.type == rhs.type &&
               lhs.message == rhs.message &&
               lhs.underlyingError == rhs.underlyingError &&
               lhs.retryAfter == rhs.retryAfter
    }
}
extension UserFacingError {

    public static func from(_ failure: NetworkFailure) -> UserFacingError {
        switch failure.type {
        case .dataCenterNotResponding:
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "Connection Issue",
                message: "Unable to reach the server. Please check your internet connection and try again.",
                canRetry: true
            )

        case .authenticationRequired:
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "Authentication Required",
                message: "Please sign in to continue.",
                canRetry: false
            )

        case .sessionExpired:
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "Session Expired",
                message: "Your session has expired. Please sign in again.",
                canRetry: false
            )

        case .invalidRequest:
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "Invalid Request",
                message: "The request was not valid. Please try again.",
                canRetry: false
            )

        case .serverError:
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "Server Error",
                message: "The server encountered an error. Please try again later.",
                canRetry: true
            )

        case .timeout:
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "Request Timeout",
                message: "The request took too long. Please check your connection and try again.",
                canRetry: true
            )

        case .networkUnavailable, .unavailable, .connectionFailed:
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "No Internet Connection",
                message: "Please check your internet connection and try again.",
                canRetry: true
            )

        case .operationCancelled, .cancelled:
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "Operation Cancelled",
                message: "The operation was cancelled.",
                canRetry: false
            )

        case .rateLimited:
            let retryMessage = failure.retryAfter != nil
                ? "Please wait \(Int(failure.retryAfter!)) seconds before trying again."
                : "Please try again in a few moments."
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "Too Many Requests",
                message: retryMessage,
                canRetry: true
            )

        case .encryptionFailed, .decryptionFailed:
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "Security Error",
                message: "A security error occurred. Please try again or contact support if the problem persists.",
                canRetry: false
            )

        default:
            return UserFacingError(
                errorCode: failure.type.rawValue,
                title: "Unknown Error",
                message: "An unexpected error occurred. Please try again.",
                canRetry: true
            )
        }
    }
}
