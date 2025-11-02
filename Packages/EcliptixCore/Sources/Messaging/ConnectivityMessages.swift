import Foundation


public struct ConnectivityIntentMessage: Message {
    public let messageId: UUID
    public let timestamp: Date
    public let intent: ConnectivityIntent

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        intent: ConnectivityIntent
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.intent = intent
    }
}

public struct ConnectivitySnapshotMessage: Message {
    public let messageId: UUID
    public let timestamp: Date
    public let snapshot: ConnectivitySnapshot

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        snapshot: ConnectivitySnapshot
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.snapshot = snapshot
    }
}

public struct ConnectivityRestoredMessage: Message {
    public let messageId: UUID
    public let timestamp: Date
    public let previousStatus: ConnectivityStatus
    public let restoredAt: Date

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        previousStatus: ConnectivityStatus,
        restoredAt: Date = Date()
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.previousStatus = previousStatus
        self.restoredAt = restoredAt
    }
}


public struct ManualRetryRequestedMessage: Message {
    public let messageId: UUID
    public let timestamp: Date
    public let source: ManualRetrySource
    public let connectId: UInt32?

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        source: ManualRetrySource = .userAction,
        connectId: UInt32? = nil
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.source = source
        self.connectId = connectId
    }
}

public enum ManualRetrySource: Sendable {
    case userAction
    case automatic
    case systemRecovery
}

public struct ManualRetryResponseMessage: MessageResponse {
    public let messageId: UUID
    public let timestamp: Date
    public let correlationId: UUID
    public let requestId: UUID
    public let retriedCount: Int
    public let successCount: Int
    public let failureCount: Int

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        correlationId: UUID,
        requestId: UUID,
        retriedCount: Int,
        successCount: Int,
        failureCount: Int
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.correlationId = correlationId
        self.requestId = requestId
        self.retriedCount = retriedCount
        self.successCount = successCount
        self.failureCount = failureCount
    }
}


public struct RetriesExhaustedMessage: Message {
    public let messageId: UUID
    public let timestamp: Date
    public let connectId: UInt32?
    public let operationName: String?
    public let totalAttempts: Int
    public let failure: NetworkFailure

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        connectId: UInt32? = nil,
        operationName: String? = nil,
        totalAttempts: Int,
        failure: NetworkFailure
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.connectId = connectId
        self.operationName = operationName
        self.totalAttempts = totalAttempts
        self.failure = failure
    }
}


public struct ConnectionRecoveryRequestedMessage: Message {
    public let messageId: UUID
    public let timestamp: Date
    public let reason: ConnectionRecoveryReason
    public let connectId: UInt32?
    public let failure: NetworkFailure?

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        reason: ConnectionRecoveryReason,
        connectId: UInt32? = nil,
        failure: NetworkFailure? = nil
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.reason = reason
        self.connectId = connectId
        self.failure = failure
    }
}

public enum ConnectionRecoveryReason: Sendable {
    case protocolStateMismatch
    case handshakeFailed
    case manualRequest
    case automaticRecovery
}

public struct ConnectionRecoveryResponseMessage: MessageResponse {
    public let messageId: UUID
    public let timestamp: Date
    public let correlationId: UUID
    public let requestId: UUID
    public let success: Bool
    public let newConnectId: UInt32?
    public let error: NetworkFailure?

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        correlationId: UUID,
        requestId: UUID,
        success: Bool,
        newConnectId: UInt32? = nil,
        error: NetworkFailure? = nil
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.correlationId = correlationId
        self.requestId = requestId
        self.success = success
        self.newConnectId = newConnectId
        self.error = error
    }
}


public struct OperationStartedMessage: Message {
    public let messageId: UUID
    public let timestamp: Date
    public let operationId: UUID
    public let operationName: String
    public let connectId: UInt32?

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        operationId: UUID,
        operationName: String,
        connectId: UInt32? = nil
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.operationId = operationId
        self.operationName = operationName
        self.connectId = connectId
    }
}

public struct OperationCompletedMessage: Message {
    public let messageId: UUID
    public let timestamp: Date
    public let operationId: UUID
    public let operationName: String
    public let success: Bool
    public let error: NetworkFailure?
    public let duration: TimeInterval

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        operationId: UUID,
        operationName: String,
        success: Bool,
        error: NetworkFailure? = nil,
        duration: TimeInterval
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.operationId = operationId
        self.operationName = operationName
        self.success = success
        self.error = error
        self.duration = duration
    }
}
