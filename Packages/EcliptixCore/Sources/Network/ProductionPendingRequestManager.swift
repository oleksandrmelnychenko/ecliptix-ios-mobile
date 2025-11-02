@preconcurrency import Combine
import Foundation


public protocol TypedPendingRequest: Sendable {
    associatedtype ResultType
    var id: UUID { get }
    var connectId: UInt32? { get }
    var enqueuedAt: Date { get }
    func execute() async throws -> ResultType
}

public struct ConcretePendingRequest<T>: TypedPendingRequest {
    public let id: UUID
    public let connectId: UInt32?
    public let enqueuedAt: Date
    private let operation: @Sendable () async throws -> T

    public init(
        id: UUID = UUID(),
        connectId: UInt32? = nil,
        enqueuedAt: Date = Date(),
        operation: @escaping @Sendable () async throws -> T
    ) {
        self.id = id
        self.connectId = connectId
        self.enqueuedAt = enqueuedAt
        self.operation = operation
    }

    public func execute() async throws -> T {
        try await operation()
    }
}


public actor ProductionPendingRequestManager {
    private var pendingRequests: [UUID: @Sendable () async throws -> Void] = [:]

    private var typedPendingRequests: [UUID: Any] = [:]

    private var requestMetadata: [UUID: RequestMetadata] = [:]

    private var retryingRequests: Set<UUID> = []

    private var cancellationTasks: [UUID: Task<Void, Never>] = [:]

    private var isRetryingAll = false

    private var stats = Statistics()

    private let maxQueueSize: Int
    private let maxRequestAge: TimeInterval

    private let messageBus: MessageBus

    private var connectivitySubscription: AnyCancellable?

    private struct RequestMetadata {
        let id: UUID
        let connectId: UInt32?
        let enqueuedAt: Date
        let operationName: String?
        var retryCount: Int

        var isExpired: Bool {
            Date().timeIntervalSince(enqueuedAt) > 300
        }
    }

    private struct Statistics {
        var totalQueued: Int = 0
        var totalProcessed: Int = 0
        var totalFailed: Int = 0
        var totalRequeued: Int = 0
    }

    public init(
        maxQueueSize: Int = 100,
        maxRequestAge: TimeInterval = 300,
        messageBus: MessageBus = GlobalMessageBus
    ) {
        self.maxQueueSize = maxQueueSize
        self.maxRequestAge = maxRequestAge
        self.messageBus = messageBus

        Log.info("[ProductionPendingRequestManager] Initialized (maxQueue: \(maxQueueSize), maxAge: \(String(format: "%.0fs", maxRequestAge)))")

        Task { [weak self] in
            await self?.setupMessageBusSubscriptions()
        }
    }

    @discardableResult
    public func enqueue(
        connectId: UInt32? = nil,
        operationName: String? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) -> UUID {
        let id = UUID()

        if pendingRequests.count + typedPendingRequests.count >= maxQueueSize {
            Log.warning("[ProductionPendingRequestManager] Queue full (\(maxQueueSize)), dropping oldest request")
            removeOldestRequest()
        }

        pendingRequests[id] = operation

        requestMetadata[id] = RequestMetadata(
            id: id,
            connectId: connectId,
            enqueuedAt: Date(),
            operationName: operationName,
            retryCount: 0
        )

        stats.totalQueued += 1

        Log.info("[ProductionPendingRequestManager] Queued request [ID: \(id)] (queue: \(getTotalQueueSize()))")

        return id
    }

    @discardableResult
    public func enqueueTyped<T>(
        connectId: UInt32? = nil,
        operationName: String? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) -> UUID {
        let id = UUID()

        if pendingRequests.count + typedPendingRequests.count >= maxQueueSize {
            Log.warning("[ProductionPendingRequestManager] Queue full (\(maxQueueSize)), dropping oldest request")
            removeOldestRequest()
        }

        let request = ConcretePendingRequest(
            id: id,
            connectId: connectId,
            enqueuedAt: Date(),
            operation: operation
        )

        typedPendingRequests[id] = request

        requestMetadata[id] = RequestMetadata(
            id: id,
            connectId: connectId,
            enqueuedAt: Date(),
            operationName: operationName,
            retryCount: 0
        )

        stats.totalQueued += 1

        Log.info("[ProductionPendingRequestManager] Queued typed request [ID: \(id)] (queue: \(getTotalQueueSize()))")

        return id
    }

    @discardableResult
    public func retryAllPendingRequests() async -> (total: Int, success: Int, failure: Int) {
        guard !isRetryingAll else {
            Log.debug("[ProductionPendingRequestManager] Already retrying all requests")
            return (0, 0, 0)
        }

        isRetryingAll = true
        defer { isRetryingAll = false }

        cleanExpiredRequests()

        let untypedToRetry = pendingRequests.filter { id, _ in
            !retryingRequests.contains(id)
        }

        let typedToRetry = typedPendingRequests.filter { id, _ in
            !retryingRequests.contains(id)
        }

        let totalCount = untypedToRetry.count + typedToRetry.count

        guard totalCount > 0 else {
            Log.debug("[ProductionPendingRequestManager] No requests to retry")
            return (0, 0, 0)
        }

        Log.info("[ProductionPendingRequestManager] Retrying \(totalCount) pending requests...")

        for id in untypedToRetry.keys {
            retryingRequests.insert(id)
        }
        for id in typedToRetry.keys {
            retryingRequests.insert(id)
        }

        let results = await withTaskGroup(of: (UUID, Bool).self) { group in
            for (id, operation) in untypedToRetry {
                group.addTask {
                    do {
                        try await operation()
                        return (id, true)
                    } catch {
                        Log.warning("[ProductionPendingRequestManager] Request \(id) failed: \(error)")
                        return (id, false)
                    }
                }
            }

            for (id, anyRequest) in typedToRetry {
                guard let request = anyRequest as? any TypedPendingRequest else {
                    continue
                }

                group.addTask { [id] in
                    do {
                        _ = try await request.execute()
                        return (id, true)
                    } catch {
                        Log.warning("[ProductionPendingRequestManager] Typed request \(id) failed: \(error)")
                        return (id, false)
                    }
                }
            }

            var successIds: Set<UUID> = []
            var failureIds: Set<UUID> = []

            for await (id, success) in group {
                if success {
                    successIds.insert(id)
                } else {
                    failureIds.insert(id)
                }
            }

            return (successIds, failureIds)
        }

        let (successIds, failureIds) = results

        for id in successIds {
            pendingRequests.removeValue(forKey: id)
            typedPendingRequests.removeValue(forKey: id)
            requestMetadata.removeValue(forKey: id)
            retryingRequests.remove(id)
            stats.totalProcessed += 1
        }

        for id in failureIds {
            if var metadata = requestMetadata[id] {
                metadata.retryCount += 1
                requestMetadata[id] = metadata

                retryingRequests.remove(id)
                stats.totalRequeued += 1
            }
            stats.totalFailed += 1
        }

        let successCount = successIds.count
        let failureCount = failureIds.count

        Log.info("[ProductionPendingRequestManager] Retry complete: \(successCount) success, \(failureCount) failed")

        await messageBus.publish(ManualRetryResponseMessage(
            correlationId: UUID(),
            requestId: UUID(),
            retriedCount: totalCount,
            successCount: successCount,
            failureCount: failureCount
        ))

        return (totalCount, successCount, failureCount)
    }

    @discardableResult
    public func cancel(requestId: UUID) -> Bool {
        let removed = pendingRequests.removeValue(forKey: requestId) != nil ||
                      typedPendingRequests.removeValue(forKey: requestId) != nil

        if removed {
            requestMetadata.removeValue(forKey: requestId)
            retryingRequests.remove(requestId)
            cancellationTasks[requestId]?.cancel()
            cancellationTasks.removeValue(forKey: requestId)

            Log.debug("[ProductionPendingRequestManager] Cancelled request \(requestId)")
        }

        return removed
    }

    public func clearQueue() {
        let count = getTotalQueueSize()

        pendingRequests.removeAll()
        typedPendingRequests.removeAll()
        requestMetadata.removeAll()
        retryingRequests.removeAll()
        cancellationTasks.values.forEach { $0.cancel() }
        cancellationTasks.removeAll()

        Log.info("[ProductionPendingRequestManager] Cleared queue (\(count) requests)")
    }

    public func getQueueSize() -> Int {
        getTotalQueueSize()
    }

    public func isEmpty() -> Bool {
        getTotalQueueSize() == 0
    }

    public func isFull() -> Bool {
        getTotalQueueSize() >= maxQueueSize
    }

    public func getStatistics() -> (queued: Int, processed: Int, failed: Int, requeued: Int) {
        (stats.totalQueued, stats.totalProcessed, stats.totalFailed, stats.totalRequeued)
    }

    private func getTotalQueueSize() -> Int {
        pendingRequests.count + typedPendingRequests.count
    }

    private func removeOldestRequest() {
        if let oldestId = requestMetadata
            .min(by: { $0.value.enqueuedAt < $1.value.enqueuedAt })?
            .key {
            _ = cancel(requestId: oldestId)
        }
    }

    private func cleanExpiredRequests() {
        let expiredIds = requestMetadata.filter { $0.value.isExpired }.map { $0.key }

        for id in expiredIds {
            _ = cancel(requestId: id)
        }

        if !expiredIds.isEmpty {
            Log.info("[ProductionPendingRequestManager] Cleaned \(expiredIds.count) expired requests")
        }
    }

    private func setupMessageBusSubscriptions() {
        Task {
            connectivitySubscription = await messageBus.subscribe(
                lifetime: .strong
            ) { [weak self] (message: ConnectivityRestoredMessage) in
                await self?.handleConnectivityRestored(message)
            }

            let _ = await messageBus.subscribe(
                lifetime: .strong
            ) { [weak self] (message: ManualRetryRequestedMessage) in
                await self?.handleManualRetryRequest(message)
            }
        }
    }

    private func handleConnectivityRestored(_ message: ConnectivityRestoredMessage) async {
        Log.info("[ProductionPendingRequestManager] Connectivity restored, retrying pending requests...")
        await retryAllPendingRequests()
    }

    private func handleManualRetryRequest(_ message: ManualRetryRequestedMessage) async {
        Log.info("[ProductionPendingRequestManager] Manual retry requested")
        await retryAllPendingRequests()
    }
}

extension ProductionPendingRequestManager: CustomStringConvertible {
    nonisolated public var description: String {
        return "ProductionPendingRequestManager"
    }
}

extension TypedPendingRequest {
    fileprivate func execute() async throws -> Any {
        try await execute() as ResultType
    }
}
