import Foundation
import Combine
import EcliptixCore

// MARK: - Pending Request Manager
/// Manages pending requests that failed due to network outages for later retry
/// Migrated from: Ecliptix.Core/Services/Network/Infrastructure/PendingRequestManager.cs
@MainActor
public final class PendingRequestManager {

    // MARK: - Types

    /// A pending request that can be retried
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

    // MARK: - Properties

    private var pendingRequests: [String: PendingRequest] = [:]
    private let requestsLock = NSLock()
    private let retryAllSemaphore = NSLock() // Ensures only one retry-all operation at a time

    /// Publisher for pending request count changes
    public let pendingCountPublisher = PassthroughSubject<Int, Never>()

    /// Current count of pending requests
    public var pendingRequestCount: Int {
        requestsLock.lock()
        defer { requestsLock.unlock() }
        return pendingRequests.count
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Register Pending Request

    /// Registers a request as pending for later retry
    /// Migrated from: RegisterPendingRequest()
    public func registerPendingRequest(
        requestId: String,
        retryAction: @escaping () async throws -> Void
    ) {
        requestsLock.lock()
        defer { requestsLock.unlock() }

        // Don't register if already exists
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
        Log.info("[PendingRequestManager] 📝 REGISTERED: Request '\(requestId)'. Total pending: \(newCount)")

        // Notify count changed
        Task { @MainActor in
            pendingCountPublisher.send(newCount)
        }
    }

    // MARK: - Remove Pending Request

    /// Removes a pending request
    /// Migrated from: RemovePendingRequest()
    public func removePendingRequest(requestId: String) {
        requestsLock.lock()
        defer { requestsLock.unlock() }

        guard let request = pendingRequests.removeValue(forKey: requestId) else {
            return
        }

        request.cancellationToken.cancel()

        let newCount = pendingRequests.count
        Log.debug("[PendingRequestManager] 🗑️ REMOVED: Request '\(requestId)'. Remaining: \(newCount)")

        // Notify count changed
        Task { @MainActor in
            pendingCountPublisher.send(newCount)
        }
    }

    // MARK: - Retry All Pending Requests

    /// Retries all pending requests
    /// Migrated from: RetryAllPendingRequestsAsync()
    /// Returns the number of requests that succeeded
    public func retryAllPendingRequests() async -> Int {
        // Ensure only one retry-all operation at a time
        guard retryAllSemaphore.try() else {
            Log.debug("[PendingRequestManager] Retry-all already in progress, skipping")
            return 0
        }
        defer { retryAllSemaphore.unlock() }

        // Get snapshot of pending requests
        requestsLock.lock()
        let requests = Array(pendingRequests.values)
        requestsLock.unlock()

        guard !requests.isEmpty else {
            Log.debug("[PendingRequestManager] No pending requests to retry")
            return 0
        }

        Log.info("[PendingRequestManager] 🔄 RETRY ALL: Starting retry for \(requests.count) pending requests")

        var successCount = 0

        // Retry each request
        for request in requests {
            // Skip if cancelled
            guard !request.cancellationToken.isCancelled else {
                Log.debug("[PendingRequestManager] Skipping cancelled request '\(request.requestId)'")
                continue
            }

            do {
                Log.debug("[PendingRequestManager] Retrying request '\(request.requestId)'...")

                // Execute retry action
                try await request.retryAction()

                // Success - remove from pending
                removePendingRequest(requestId: request.requestId)
                successCount += 1

                Log.info("[PendingRequestManager] ✅ SUCCESS: Request '\(request.requestId)' succeeded on retry")

            } catch {
                Log.warning("[PendingRequestManager] ❌ FAILED: Request '\(request.requestId)' failed on retry: \(error.localizedDescription)")
                // Keep in pending for next retry attempt
            }
        }

        Log.info("[PendingRequestManager] 🔄 RETRY COMPLETE: \(successCount)/\(requests.count) requests succeeded")

        return successCount
    }

    // MARK: - Cancel All

    /// Cancels all pending requests
    public func cancelAllPendingRequests() {
        requestsLock.lock()
        defer { requestsLock.unlock() }

        for request in pendingRequests.values {
            request.cancellationToken.cancel()
        }

        let count = pendingRequests.count
        pendingRequests.removeAll()

        Log.info("[PendingRequestManager] 🚫 CANCELLED ALL: Cancelled and removed \(count) pending requests")

        Task { @MainActor in
            pendingCountPublisher.send(0)
        }
    }

    // MARK: - Cleanup Old Requests

    /// Removes pending requests older than the specified age
    public func cleanupOldRequests(olderThan age: TimeInterval) {
        requestsLock.lock()
        defer { requestsLock.unlock() }

        let cutoff = Date().addingTimeInterval(-age)
        let oldRequests = pendingRequests.filter { $0.value.createdAt < cutoff }

        for (requestId, request) in oldRequests {
            request.cancellationToken.cancel()
            pendingRequests.removeValue(forKey: requestId)
        }

        if !oldRequests.isEmpty {
            Log.info("[PendingRequestManager] 🧹 CLEANUP: Removed \(oldRequests.count) old pending requests")

            let newCount = pendingRequests.count
            Task { @MainActor in
                pendingCountPublisher.send(newCount)
            }
        }
    }
}
