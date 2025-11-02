import EcliptixCore
import Foundation
import GRPCCore

public struct GRPCErrorProcessor: @unchecked Sendable {

    private let localizationService: LocalizationService?

    public init(localizationService: LocalizationService? = nil) {
        self.localizationService = localizationService
    }

    public func process(
        _ error: Error,
        serviceType: NetworkProvider.RPCServiceType,
        operationName: String
    ) -> NetworkFailure {

        Log.error("[GRPCErrorProcessor] Processing error for \(operationName): \(error.localizedDescription)")

        let failureType = classifyError(error)

        let userError = createUserFacingError(
            from: error,
            failureType: failureType,
            serviceType: serviceType
        )

        let isRetryable = isRetryableError(failureType, error: error)

        return NetworkFailure(
            type: failureType,
            message: userError.message,
            userError: userError,
            isRetryable: isRetryable,
            metadata: extractMetadata(from: error)
        )
    }

    private func classifyError(_ error: Error) -> NetworkFailureType {

        let errorString = error.localizedDescription.lowercased()

        if errorString.contains("unauthenticated") || errorString.contains("unauthorized") {
            return .unauthenticated
        }

        if errorString.contains("permission denied") || errorString.contains("forbidden") {
            return .permissionDenied
        }

        if isProtocolStateMismatch(error) {
            return .protocolStateMismatch
        }

        if errorString.contains("timeout") || errorString.contains("deadline exceeded") {
            return .timeout
        }

        if errorString.contains("unavailable") || errorString.contains("connection refused") {
            return .connectionFailed
        }

        if errorString.contains("cancelled") || errorString.contains("canceled") {
            return .cancelled
        }

        if errorString.contains("not found") {
            return .notFound
        }

        if errorString.contains("already exists") {
            return .alreadyExists
        }

        if errorString.contains("invalid argument") || errorString.contains("validation") {
            return .invalidArgument
        }

        return .unknown
    }

    private func isProtocolStateMismatch(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()

        let patterns = [
            "header authentication failed",
            "sequence mismatch",
            "chain rotation",
            "protocol state mismatch",
            "invalid ratchet index",
            "decryption failed",
            "authentication tag"
        ]

        return patterns.contains { errorString.contains($0) }
    }

    private func isRetryableError(_ failureType: NetworkFailureType, error: Error) -> Bool {
        switch failureType {

        case .timeout, .connectionFailed, .unavailable, .rateLimited:
            return true

        case .unauthenticated, .permissionDenied, .invalidArgument,
             .notFound, .alreadyExists, .failedPrecondition:
            return false

        case .protocolStateMismatch, .handshakeFailed:
            return true

        case .cancelled:
            return false

        case .unknown, .serverError, .serialization:
            return true

        default:
            return false
        }
    }

    private func createUserFacingError(
        from error: Error,
        failureType: NetworkFailureType,
        serviceType: NetworkProvider.RPCServiceType
    ) -> UserFacingError {

        let message = getLocalizedMessage(for: failureType, serviceType: serviceType)

        return UserFacingError(
            errorCode: failureType.rawValue,
            message: message,
            localizedKey: nil
        )
    }

    private func getLocalizedMessage(
        for failureType: NetworkFailureType,
        serviceType: NetworkProvider.RPCServiceType
    ) -> String {

        switch failureType {
        case .timeout:
            return "The request timed out. Please check your connection and try again."

        case .connectionFailed:
            return "Unable to connect to the server. Please check your internet connection."

        case .unauthenticated:
            return "Your session has expired. Please sign in again."

        case .permissionDenied:
            return "You don't have permission to perform this action."

        case .notFound:
            return "The requested resource was not found."

        case .alreadyExists:
            return "This resource already exists."

        case .invalidArgument:
            return "The provided information is invalid. Please check and try again."

        case .protocolStateMismatch:
            return "Communication error occurred. Reconnecting..."

        case .handshakeFailed:
            return "Failed to establish secure connection. Retrying..."

        case .unavailable:
            return "The service is temporarily unavailable. Please try again later."

        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."

        case .cancelled:
            return "The operation was cancelled."

        case .serverError:
            return "A server error occurred. Please try again later."

        case .serialization:
            return "Failed to process the response. Please try again."

        case .unknown:
            return "An unexpected error occurred. Please try again."

        default:
            return "An error occurred. Please try again."
        }
    }

    private func extractMetadata(from error: Error) -> [String: String] {
        let metadata: [String: String] = [:]

        return metadata
    }
}

extension GRPCErrorProcessor {

    public static let `default` = GRPCErrorProcessor()
}

public enum ErrorI18nKeys {
    public static let unauthenticated = "error.unauthenticated"
    public static let permissionDenied = "error.permission_denied"
    public static let timeout = "error.timeout"
    public static let connectionFailed = "error.connection_failed"
    public static let notFound = "error.not_found"
    public static let alreadyExists = "error.already_exists"
    public static let invalidArgument = "error.invalid_argument"
    public static let protocolStateMismatch = "error.protocol_state_mismatch"
    public static let handshakeFailed = "error.handshake_failed"
    public static let unavailable = "error.unavailable"
    public static let rateLimited = "error.rate_limited"
    public static let serverError = "error.server_error"
    public static let unknown = "error.unknown"
}
