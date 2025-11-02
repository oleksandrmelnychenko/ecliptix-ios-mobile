import Foundation

public enum ConnectivityStatus: Sendable {
    case connected
    case connecting
    case disconnected
    case recovering
    case unavailable
    case shuttingDown
    case retriesExhausted
}

public enum ConnectivitySource: Sendable {
    case system
    case dataCenter
    case internetProbe
    case manualAction
}

public enum ConnectivityReason: Sendable {
    case none
    case handshakeStarted
    case handshakeSucceeded
    case rpcFailure
    case manualRetry
    case backoff
    case noInternet
    case internetRecovered
    case serverShutdown
    case retryLimitReached
    case operationCancelled
    case handshakeFailed
    case securityError
    case unknown
}

public struct ConnectivitySnapshot: Sendable {
    public let status: ConnectivityStatus
    public let reason: ConnectivityReason
    public let source: ConnectivitySource
    public let failure: NetworkFailure?
    public let connectId: UInt32?
    public let retryAttempt: Int?
    public let retryBackoff: TimeInterval?
    public let correlationId: UUID
    public let occurredAt: Date

    public init(
        status: ConnectivityStatus,
        reason: ConnectivityReason,
        source: ConnectivitySource,
        failure: NetworkFailure? = nil,
        connectId: UInt32? = nil,
        retryAttempt: Int? = nil,
        retryBackoff: TimeInterval? = nil,
        correlationId: UUID = UUID(),
        occurredAt: Date = Date()
    ) {
        self.status = status
        self.reason = reason
        self.source = source
        self.failure = failure
        self.connectId = connectId
        self.retryAttempt = retryAttempt
        self.retryBackoff = retryBackoff
        self.correlationId = correlationId
        self.occurredAt = occurredAt
    }

    public static let initial = ConnectivitySnapshot(
        status: .connected,
        reason: .none,
        source: .system,
        failure: nil,
        connectId: nil,
        retryAttempt: nil,
        retryBackoff: nil,
        correlationId: .init(),
        occurredAt: Date.distantPast
    )
}

public struct ConnectivityIntent: Sendable {
    public let status: ConnectivityStatus
    public let reason: ConnectivityReason
    public let source: ConnectivitySource
    public let failure: NetworkFailure?
    public let connectId: UInt32?
    public let retryAttempt: Int?
    public let retryBackoff: TimeInterval?
    public let correlationId: UUID?

    public init(
        status: ConnectivityStatus,
        reason: ConnectivityReason,
        source: ConnectivitySource,
        failure: NetworkFailure? = nil,
        connectId: UInt32? = nil,
        retryAttempt: Int? = nil,
        retryBackoff: TimeInterval? = nil,
        correlationId: UUID? = nil
    ) {
        self.status = status
        self.reason = reason
        self.source = source
        self.failure = failure
        self.connectId = connectId
        self.retryAttempt = retryAttempt
        self.retryBackoff = retryBackoff
        self.correlationId = correlationId
    }

    public static func connected(
        connectId: UInt32? = nil,
        reason: ConnectivityReason = .handshakeSucceeded
    ) -> ConnectivityIntent {
        ConnectivityIntent(
            status: .connected,
            reason: reason,
            source: .dataCenter,
            connectId: connectId
        )
    }

    public static func connecting(
        connectId: UInt32? = nil,
        reason: ConnectivityReason = .handshakeStarted,
        source: ConnectivitySource = .dataCenter
    ) -> ConnectivityIntent {
        ConnectivityIntent(
            status: .connecting,
            reason: reason,
            source: source,
            connectId: connectId
        )
    }

    public static func disconnected(
        failure: NetworkFailure,
        connectId: UInt32? = nil,
        reason: ConnectivityReason = .rpcFailure,
        source: ConnectivitySource = .dataCenter
    ) -> ConnectivityIntent {
        ConnectivityIntent(
            status: .disconnected,
            reason: reason,
            source: source,
            failure: failure,
            connectId: connectId
        )
    }

    public static func recovering(
        failure: NetworkFailure,
        connectId: UInt32? = nil,
        retryAttempt: Int? = nil,
        backoff: TimeInterval? = nil
    ) -> ConnectivityIntent {
        ConnectivityIntent(
            status: .recovering,
            reason: .backoff,
            source: .system,
            failure: failure,
            connectId: connectId,
            retryAttempt: retryAttempt,
            retryBackoff: backoff
        )
    }

    public static func retriesExhausted(
        failure: NetworkFailure,
        connectId: UInt32? = nil,
        retries: Int? = nil
    ) -> ConnectivityIntent {
        ConnectivityIntent(
            status: .retriesExhausted,
            reason: .retryLimitReached,
            source: .system,
            failure: failure,
            connectId: connectId,
            retryAttempt: retries
        )
    }

    public static func internetLost() -> ConnectivityIntent {
        ConnectivityIntent(
            status: .unavailable,
            reason: .noInternet,
            source: .internetProbe
        )
    }

    public static func internetRecovered() -> ConnectivityIntent {
        ConnectivityIntent(
            status: .connecting,
            reason: .internetRecovered,
            source: .internetProbe
        )
    }

    public static func manualRetry(connectId: UInt32? = nil) -> ConnectivityIntent {
        ConnectivityIntent(
            status: .connecting,
            reason: .manualRetry,
            source: .manualAction,
            connectId: connectId
        )
    }

    public static func serverShutdown(failure: NetworkFailure) -> ConnectivityIntent {
        ConnectivityIntent(
            status: .shuttingDown,
            reason: .serverShutdown,
            source: .dataCenter,
            failure: failure
        )
    }
}

extension ConnectivitySnapshot: CustomStringConvertible {
    public var description: String {
        var parts = [
            "Status: \(status)",
            "Source: \(source)",
            "Reason: \(reason)"
        ]

        if let connectId = connectId {
            parts.append("ConnectId: \(connectId)")
        }

        if let retryAttempt = retryAttempt {
            parts.append("Retry: \(retryAttempt)")
        }

        if let backoff = retryBackoff {
            parts.append("Backoff: \(String(format: "%.1fs", backoff))")
        }

        return "ConnectivitySnapshot(\(parts.joined(separator: ", ")))"
    }
}

extension ConnectivityReason {

    public static func from(networkFailure: NetworkFailure?) -> ConnectivityReason {
        guard let failure = networkFailure else {
            return .unknown
        }

        switch failure.type {
        case .serviceUnavailable:
            return .serverShutdown
        case .operationCancelled:
            return .operationCancelled
        case .authenticationFailed,
             .unauthorized,
             .forbidden:
            return .securityError
        case .connectionTimeout,
             .serverNotResponding:
            return .handshakeFailed
        case .serverError,
             .gatewayTimeout:
            return .rpcFailure
        default:
            return .unknown
        }
    }
}
