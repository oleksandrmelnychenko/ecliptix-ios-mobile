import Combine
import EcliptixCore
import Foundation

@MainActor
public final class PendingRequestManager {

    private struct PendingRequest {
        let requestId: String
        let createdAt: Date
        let retryAction: () async throws -> Void
        let cancellationToken: CancellationTokenSource

        class CancellationTokenSource {
            private(set) var isCancelled: Bool = false

            func cancel() {
                isCancelled = true
            }
        }
    }

    private var pendingRequests: [String: PendingRequest] = [:]
    private var isRetryAllInProgress: Bool = false
    private var processedCount: Int = 0
    private var failedCount: Int = 0

    public let pendingCountPublisher = PassthroughSubject<Int, Never>()

    public var pendingRequestCount: Int {
        return pendingRequests.count
    }

    public var queueSize: Int {
        return pendingRequests.count
    }

    public var statistics: (queued: Int, processed: Int, failed: Int) {
        return (pendingRequests.count, processedCount, failedCount)
    }

    public init() {}

    public func clearQueue() {
        cancelAllPendingRequests()
    }

    public func registerPendingRequest(
        requestId: String,
        retryAction: @escaping () async throws -> Void
    ) {

        guard pendingRequests[requestId] == nil else {
            Log.debug("[PendingRequestManager] Request '\(requestId)' already pending")
            return
        }

        let cancellationToken = PendingRequest.CancellationTokenSource()

        let request = PendingRequest(
            requestId: requestId,
            createdAt: Date(),
            retryAction: retryAction,
            cancellationToken: cancellationToken
        )

        pendingRequests[requestId] = request

        let newCount = pendingRequests.count
        Log.info("[PendingRequestManager]  REGISTERED: Request '\(requestId)'. Total pending: \(newCount)")

        pendingCountPublisher.send(newCount)
    }

    public func removePendingRequest(requestId: String) {
        guard let request = pendingRequests.removeValue(forKey: requestId) else {
            return
        }

        request.cancellationToken.cancel()

        let newCount = pendingRequests.count
        Log.debug("[PendingRequestManager]  REMOVED: Request '\(requestId)'. Remaining: \(newCount)")

        pendingCountPublisher.send(newCount)
    }

    public func retryAllPendingRequests() async -> Int {

        guard !isRetryAllInProgress else {
            Log.debug("[PendingRequestManager] Retry-all already in progress, skipping")
            return 0
        }

        isRetryAllInProgress = true
        defer { isRetryAllInProgress = false }

        let requests = Array(pendingRequests.values)

        guard !requests.isEmpty else {
            Log.debug("[PendingRequestManager] No pending requests to retry")
            return 0
        }

        Log.info("[PendingRequestManager]  RETRY ALL: Starting retry for \(requests.count) pending requests")

        var successCount = 0

        for request in requests {

            guard !request.cancellationToken.isCancelled else {
                Log.debug("[PendingRequestManager] Skipping cancelled request '\(request.requestId)'")
                continue
            }

            do {
                Log.debug("[PendingRequestManager] Retrying request '\(request.requestId)'...")

                try await request.retryAction()

                removePendingRequest(requestId: request.requestId)
                successCount += 1
                processedCount += 1

                Log.info("[PendingRequestManager] [OK] SUCCESS: Request '\(request.requestId)' succeeded on retry")

            } catch {
                failedCount += 1
                Log.warning("[PendingRequestManager] [FAILED] FAILED: Request '\(request.requestId)' failed on retry: \(error.localizedDescription)")

            }
        }

        Log.info("[PendingRequestManager]  RETRY COMPLETE: \(successCount)/\(requests.count) requests succeeded")

        return successCount
    }

    public func cancelAllPendingRequests() {
        for request in pendingRequests.values {
            request.cancellationToken.cancel()
        }

        let count = pendingRequests.count
        pendingRequests.removeAll()

        Log.info("[PendingRequestManager]  CANCELLED ALL: Cancelled and removed \(count) pending requests")

        pendingCountPublisher.send(0)
    }

    public func cleanupOldRequests(olderThan age: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-age)
        let oldRequests = pendingRequests.filter { $0.value.createdAt < cutoff }

        for (requestId, request) in oldRequests {
            request.cancellationToken.cancel()
            pendingRequests.removeValue(forKey: requestId)
        }

        if !oldRequests.isEmpty {
            Log.info("[PendingRequestManager]  CLEANUP: Removed \(oldRequests.count) old pending requests")

            let newCount = pendingRequests.count
            pendingCountPublisher.send(newCount)
        }
    }
}
