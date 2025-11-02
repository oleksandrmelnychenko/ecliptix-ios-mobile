import EcliptixCore
import Foundation
import GRPCCore

public struct GRPCErrorClassifier {


    public static func isBusinessError(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()

        let businessErrorPatterns = [
            "invalid argument",
            "invalidargument",
            "not found",
            "notfound",
            "already exists",
            "alreadyexists",
            "failed precondition",
            "failedprecondition",
            "out of range",
            "outofrange",
            "unimplemented"
        ]

        return businessErrorPatterns.contains { errorString.contains($0) }
    }


    public static func isAuthFlowMissing(_ error: Error, metadata: [String: String] = [:]) -> Bool {
        let errorString = error.localizedDescription.lowercased()

        if let errorCode = metadata["error-code"], errorCode.lowercased() == "authflowmissing" {
            return true
        }

        if let i18nKey = metadata["i18n-key"], i18nKey.lowercased() == "error.auth_flow_missing" {
            return true
        }

        let authFlowPatterns = [
            "auth flow missing",
            "authentication flow required",
            "no auth flow",
            "missing authentication"
        ]

        return authFlowPatterns.contains { errorString.contains($0) }
    }

    public static func isAuthenticationError(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()

        let authErrorPatterns = [
            "unauthenticated",
            "unauthorized",
            "authentication failed",
            "invalid credentials",
            "authentication required",
            "token expired",
            "invalid token"
        ]

        return authErrorPatterns.contains { errorString.contains($0) }
    }


    public static func isProtocolStateMismatch(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()

        if errorString.contains("header authentication failed") {
            return true
        }

        if (errorString.contains("requested index") && errorString.contains("not future")) ||
           errorString.contains("sequence mismatch") {
            return true
        }

        if errorString.contains("chain rotation") {
            return true
        }

        if errorString.contains("protocol state") &&
           (errorString.contains("mismatch") || errorString.contains("desynchronized")) {
            return true
        }

        if errorString.contains("dhpublic") && errorString.contains("unknown") {
            return true
        }

        if errorString.contains("sender chain") && errorString.contains("invalid") {
            return true
        }

        if errorString.contains("receiver chain") && errorString.contains("invalid") {
            return true
        }

        if errorString.contains("protocol version") {
            return true
        }

        if errorString.contains("state version") {
            return true
        }

        if errorString.contains("channel state") && errorString.contains("invalid") {
            return true
        }

        if errorString.contains("ratchet") &&
           (errorString.contains("invalid") ||
            errorString.contains("mismatch") ||
            errorString.contains("failed")) {
            return true
        }

        if errorString.contains("decryption failed") ||
           errorString.contains("authentication tag") {
            return true
        }

        return false
    }


    public static func isTransientError(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()

        if errorString.contains("cancelled") || errorString.contains("canceled") {
            return false
        }

        if isProtocolStateMismatch(error) {
            return false
        }

        if isBusinessError(error) {
            return false
        }

        if isAuthenticationError(error) {
            return false
        }

        if errorString.contains("timeout") || errorString.contains("deadline exceeded") {
            return true
        }

        if errorString.contains("unavailable") ||
           errorString.contains("connection refused") ||
           errorString.contains("connection failed") {
            return true
        }

        if errorString.contains("internal error") ||
           errorString.contains("server error") {
            return true
        }

        if errorString.contains("resource exhausted") ||
           errorString.contains("too many requests") {
            return true
        }

        return false
    }


    public static func requiresConnectionRecovery(_ error: Error) -> Bool {
        if isProtocolStateMismatch(error) {
            return true
        }

        let errorString = error.localizedDescription.lowercased()

        if errorString.contains("handshake failed") ||
           errorString.contains("handshake error") {
            return true
        }

        if errorString.contains("channel closed") ||
           errorString.contains("channel error") {
            return true
        }

        return false
    }


    public static func isServerShuttingDown(_ error: Error, metadata: [String: String] = [:]) -> Bool {
        let errorString = error.localizedDescription.lowercased()

        if let serverStatus = metadata["server-status"],
           serverStatus.lowercased().contains("shutdown") {
            return true
        }

        let shutdownPatterns = [
            "server shutting down",
            "server shutdown",
            "service unavailable",
            "maintenance mode"
        ]

        return shutdownPatterns.contains { errorString.contains($0) }
    }


    public static func shouldRetry(_ error: Error, metadata: [String: String] = [:]) -> Bool {
        let errorString = error.localizedDescription.lowercased()
        if errorString.contains("cancelled") || errorString.contains("canceled") {
            return false
        }

        if isBusinessError(error) {
            return false
        }

        if isAuthenticationError(error) {
            return false
        }

        if isServerShuttingDown(error, metadata: metadata) {
            return false
        }

        if isProtocolStateMismatch(error) {
            return false
        }

        if isTransientError(error) {
            return true
        }

        return false
    }


    public static func extractMetadata(from error: Error) -> [String: String] {
        var metadata: [String: String] = [:]

        let errorString = error.localizedDescription

        let lines = errorString.components(separatedBy: .newlines)
        for line in lines {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                metadata[key.lowercased()] = value
            }
        }

        return metadata
    }
}


public struct ErrorClassificationResult {
    public let isBusinessError: Bool
    public let isAuthenticationError: Bool
    public let isAuthFlowMissing: Bool
    public let isProtocolStateMismatch: Bool
    public let isTransientError: Bool
    public let requiresConnectionRecovery: Bool
    public let isServerShuttingDown: Bool
    public let shouldRetry: Bool
    public let metadata: [String: String]

    public init(error: Error, metadata: [String: String] = [:]) {
        let extractedMetadata = GRPCErrorClassifier.extractMetadata(from: error)
        let combinedMetadata = metadata.merging(extractedMetadata) { current, _ in current }

        self.isBusinessError = GRPCErrorClassifier.isBusinessError(error)
        self.isAuthenticationError = GRPCErrorClassifier.isAuthenticationError(error)
        self.isAuthFlowMissing = GRPCErrorClassifier.isAuthFlowMissing(error, metadata: combinedMetadata)
        self.isProtocolStateMismatch = GRPCErrorClassifier.isProtocolStateMismatch(error)
        self.isTransientError = GRPCErrorClassifier.isTransientError(error)
        self.requiresConnectionRecovery = GRPCErrorClassifier.requiresConnectionRecovery(error)
        self.isServerShuttingDown = GRPCErrorClassifier.isServerShuttingDown(error, metadata: combinedMetadata)
        self.shouldRetry = GRPCErrorClassifier.shouldRetry(error, metadata: combinedMetadata)
        self.metadata = combinedMetadata
    }
}

extension ErrorClassificationResult: CustomStringConvertible {
    public var description: String {
        """
        ErrorClassification(
          businessError: \(isBusinessError),
          authError: \(isAuthenticationError),
          authFlowMissing: \(isAuthFlowMissing),
          protocolMismatch: \(isProtocolStateMismatch),
          transient: \(isTransientError),
          needsRecovery: \(requiresConnectionRecovery),
          serverShutdown: \(isServerShuttingDown),
          shouldRetry: \(shouldRetry)
        )
        """
    }
}
