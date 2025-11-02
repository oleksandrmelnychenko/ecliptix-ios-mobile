import Combine
import Foundation

public struct PendingRequest: Sendable, Identifiable {
    public let id: UUID
    public let connectId: UInt32?
    public let enqueuedAt: Date
    public let operation: @Sendable () async throws -> Void

    public init(
        id: UUID = UUID(),
        connectId: UInt32? = nil,
        enqueuedAt: Date = Date(),
        operation: @escaping @Sendable () async throws -> Void
    ) {
        self.id = id
        self.connectId = connectId
        self.enqueuedAt = enqueuedAt
        self.operation = operation
    }
}

public actor PendingRequestManager {

    private let connectivityService: ConnectivityService
    private let maxQueueSize: Int
    private let maxRequestAge: TimeInterval

    private var pendingQueue: [PendingRequest] = []
    private var isProcessing = false

    private var cancellables = Set<AnyCancellable>()

    private var totalQueued: Int = 0
    private var totalProcessed: Int = 0
    private var totalFailed: Int = 0

    public init(
        connectivityService: ConnectivityService,
        maxQueueSize: Int = 100,
        maxRequestAge: TimeInterval = 300
    ) {
        self.connectivityService = connectivityService
        self.maxQueueSize = maxQueueSize
        self.maxRequestAge = maxRequestAge

        Task { await setupConnectivityObserver() }

        Log.info("[PendingRequestManager] Initialized (maxQueue: \(maxQueueSize), maxAge: \(String(format: "%.0fs", maxRequestAge)))")
    }


    @discardableResult
    public func enqueue(
        connectId: UInt32? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) -> UUID {
        cleanExpiredRequests()

        if pendingQueue.count >= maxQueueSize {
            Log.warning("[PendingRequestManager] [WARNING] Queue is full (\(maxQueueSize)), dropping oldest request")
            pendingQueue.removeFirst()
        }

        let request = PendingRequest(
            connectId: connectId,
            operation: operation
        )

        pendingQueue.append(request)
        totalQueued += 1

        Log.info("[PendingRequestManager]  Queued request (queue size: \(pendingQueue.count))")

        return request.id
    }

    @discardableResult
    public func cancel(requestId: UUID) -> Bool {
        if let index = pendingQueue.firstIndex(where: { $0.id == requestId }) {
            pendingQueue.remove(at: index)
            Log.debug("[PendingRequestManager] [FAILED] Cancelled request \(requestId)")
            return true
        }

        return false
    }

    public func clearQueue() {
        let count = pendingQueue.count
        pendingQueue.removeAll()

        Log.info("[PendingRequestManager]  Cleared queue (\(count) requests)")
    }

    public var queueSize: Int {
        return pendingQueue.count
    }

    public var statistics: (queued: Int, processed: Int, failed: Int) {
        return (totalQueued, totalProcessed, totalFailed)
    }

    private func setupConnectivityObserver() {

        connectivityService.connectivityRestoredPublisher
            .sink { _ in
                Task { [weak self] in
                    await self?.connectivityRestored()
                }
            }
            .store(in: &cancellables)

        Log.debug("[PendingRequestManager]  Listening for connectivity restoration")
    }

    private func connectivityRestored() {
        Log.info("[PendingRequestManager]  Connectivity restored, processing pending queue...")

        Task {
            await processPendingRequests()
        }
    }

    private func processPendingRequests() async {

        guard !isProcessing else {
            Log.debug("[PendingRequestManager] Already processing queue")
            return
        }
        isProcessing = true

        let requests = pendingQueue
        pendingQueue.removeAll()

        guard !requests.isEmpty else {
            isProcessing = false
            Log.debug("[PendingRequestManager] Queue is empty, nothing to process")
            return
        }

        Log.info("[PendingRequestManager]  Processing \(requests.count) pending requests...")

        var successCount = 0
        var failureCount = 0

        for request in requests {
            do {
                Log.debug("[PendingRequestManager]  Executing request \(request.id)...")
                try await request.operation()
                successCount += 1
                totalProcessed += 1

                Log.debug("[PendingRequestManager] [OK] Request succeeded")

            } catch {
                failureCount += 1
                totalFailed += 1

                Log.warning("[PendingRequestManager] [FAILED] Request failed: \(error.localizedDescription)")

                if let networkFailure = error as? NetworkFailure,
                   shouldRequeue(failure: networkFailure) {
                    Log.debug("[PendingRequestManager]  Re-queuing failed request")
                    _ = enqueue(connectId: request.connectId, operation: request.operation)
                }
            }
        }

        isProcessing = false

        Log.info("[PendingRequestManager] [OK] Processing complete (success: \(successCount), failed: \(failureCount))")
    }

    private func cleanExpiredRequests() {
        let now = Date()
        let initialCount = pendingQueue.count

        pendingQueue.removeAll { request in
            let age = now.timeIntervalSince(request.enqueuedAt)
            return age > maxRequestAge
        }

        let removedCount = initialCount - pendingQueue.count
        if removedCount > 0 {
            Log.info("[PendingRequestManager]  Cleaned \(removedCount) expired requests")
        }
    }

    private func shouldRequeue(failure: NetworkFailure) -> Bool {
        switch failure.type {
        case .serviceUnavailable:
            return false
        case .operationCancelled:
            return false
        case .authenticationFailed, .unauthorized, .forbidden:
            return false
        default:
            return true
        }
    }
}

extension PendingRequestManager {

    @discardableResult
    public func enqueueWithResult<T>(
        connectId: UInt32? = nil,
        operation: @escaping @Sendable () async -> Result<T, NetworkFailure>
    ) -> UUID {
        return enqueue(connectId: connectId) {
            let result = await operation()
            if case .failure(let error) = result {
                throw error
            }
        }
    }

    public var isEmpty: Bool {
        queueSize == 0
    }

    public var isFull: Bool {
        queueSize >= maxQueueSize
    }

    public var utilizationPercentage: Double {
        Double(queueSize) / Double(maxQueueSize) * 100.0
    }
}

extension PendingRequestManager: @preconcurrency CustomStringConvertible {
    public var description: String {
        let stats = statistics
        return """
        PendingRequestManager(
          queueSize: \(queueSize)/\(maxQueueSize) (\(String(format: "%.1f%%", utilizationPercentage))),
          totalQueued: \(stats.queued),
          totalProcessed: \(stats.processed),
          totalFailed: \(stats.failed),
          isProcessing: \(isProcessing)
        )
        """
    }
}
