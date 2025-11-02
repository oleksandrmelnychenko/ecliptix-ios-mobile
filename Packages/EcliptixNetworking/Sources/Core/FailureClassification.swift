import EcliptixCore
import Foundation

public struct FailureClassification {


    public static func isTransient(_ failure: NetworkFailure) -> Bool {
        if failure.type == .operationCancelled || failure.type == .cancelled {
            Log.debug("[FailureClassification] Non-transient: Operation cancelled")
            return false
        }

        if failure.type == .protocolStateMismatch {
            Log.debug("[FailureClassification] Non-transient: Protocol state mismatch (needs recovery)")
            return false
        }

        if let canRetry = failure.userError?.canRetry {
            Log.debug("[FailureClassification] Explicit retryability: \(canRetry)")
            return canRetry
        }

        let shouldRetry = failure.shouldRetry
        Log.debug("[FailureClassification] Transient: \(shouldRetry) for type: \(failure.type)")
        return shouldRetry
    }


    public static func requiresConnectionRecovery(_ failure: NetworkFailure) -> Bool {
        if failure.type == .protocolStateMismatch {
            Log.info("[FailureClassification] Connection recovery required: Protocol state mismatch")
            return true
        }

        if failure.type == .handshakeFailed {
            Log.info("[FailureClassification] Connection recovery required: Handshake failed")
            return true
        }

        if let recoveryHint = failure.metadata["requires-recovery"],
           recoveryHint.lowercased() == "true" {
            Log.info("[FailureClassification] Connection recovery required: Metadata hint")
            return true
        }

        return false
    }


    public static func retryStrategy(for failure: NetworkFailure) -> RetryStrategyType {
        if !isTransient(failure) {
            return .none
        }

        if requiresConnectionRecovery(failure) {
            return .connectionRecovery
        }

        if failure.type == .rateLimited {
            if let retryAfter = failure.retryAfter {
                return .fixedDelay(retryAfter)
            }
            return .exponentialWithJitter
        }

        if failure.type == .timeout || failure.type == .dataCenterNotResponding {
            return .exponentialWithJitter
        }

        if failure.type == .networkUnavailable || failure.type == .connectionFailed {
            return .aggressive
        }

        return .exponentialWithJitter
    }


    public static func severity(_ failure: NetworkFailure) -> FailureSeverity {
        switch failure.type {
        case .unauthenticated, .authenticationRequired, .permissionDenied, .sessionExpired:
            return .critical

        case .protocolStateMismatch, .handshakeFailed, .dataCenterNotResponding:
            return .high

        case .timeout, .unavailable, .connectionFailed, .serverError:
            return .medium

        case .rateLimited, .operationCancelled, .cancelled:
            return .low

        case .invalidArgument, .notFound, .alreadyExists, .failedPrecondition:
            return .info

        default:
            return .medium
        }
    }


    public static func shouldNotifyUser(_ failure: NetworkFailure, attemptNumber: Int) -> Bool {
        if failure.type == .unauthenticated ||
           failure.type == .authenticationRequired ||
           failure.type == .sessionExpired {
            return true
        }

        if failure.type == .invalidArgument ||
           failure.type == .notFound ||
           failure.type == .alreadyExists {
            return true
        }

        if isTransient(failure) {
            return attemptNumber >= 3
        }

        if failure.type == .protocolStateMismatch {
            return attemptNumber >= 2
        }

        return !isTransient(failure)
    }
}


public enum RetryStrategyType {
    case none
    case connectionRecovery
    case exponentialWithJitter
    case aggressive
    case fixedDelay(TimeInterval)
}

public enum FailureSeverity: String {
    case critical
    case high
    case medium
    case low
    case info
}


extension NetworkFailure {

    public var isTransient: Bool {
        FailureClassification.isTransient(self)
    }

    public var needsConnectionRecovery: Bool {
        FailureClassification.requiresConnectionRecovery(self)
    }

    public var retryStrategyType: RetryStrategyType {
        FailureClassification.retryStrategy(for: self)
    }

    public var severity: FailureSeverity {
        FailureClassification.severity(self)
    }

    public func shouldNotifyUser(attemptNumber: Int) -> Bool {
        FailureClassification.shouldNotifyUser(self, attemptNumber: attemptNumber)
    }
}


extension FailureClassification {

    public static func logAnalysis(_ failure: NetworkFailure, attemptNumber: Int = 1) {
        let isTransientValue = isTransient(failure)
        let needsRecovery = requiresConnectionRecovery(failure)
        let strategy = retryStrategy(for: failure)
        let severityValue = severity(failure)
        let shouldNotify = shouldNotifyUser(failure, attemptNumber: attemptNumber)

        Log.debug("""
        [FailureClassification] Analysis:
          Type: \(failure.type)
          Transient: \(isTransientValue)
          Needs Recovery: \(needsRecovery)
          Strategy: \(strategy)
          Severity: \(severityValue)
          Notify User: \(shouldNotify)
          Attempt: \(attemptNumber)
          Message: \(failure.message)
        """)
    }
}
