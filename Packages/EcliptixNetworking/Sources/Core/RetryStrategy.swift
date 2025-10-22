import Foundation
import EcliptixCore

// MARK: - Enhanced Retry Strategy
/// Comprehensive retry strategy with operation tracking, exhaustion detection, and manual retry
/// Migrated from: Ecliptix.Core/Services/Network/Resilience/RetryStrategy.cs (874 lines)
@MainActor
public final class RetryStrategy {

    // MARK: - Configuration
    private let configuration: RetryConfiguration
    private let maxTrackedOperations: Int = 1000
    private let cleanupInterval: TimeInterval = 300 // 5 minutes
    private let operationTimeout: TimeInterval = 600 // 10 minutes

    // MARK: - Operation Tracking
    private var activeOperations: [String: RetryOperationInfo] = [:]
    private var retryDelaysCache: [String: [TimeInterval]] = [:]
    private let operationsLock = NSLock()

    // MARK: - Cleanup Timer
    private var cleanupTimer: Timer?

    // MARK: - Types

    /// Information about a tracked retry operation
    private class RetryOperationInfo {
        let operationName: String
        let connectId: UInt32
        let startTime: Date
        let maxRetries: Int
        let uniqueKey: String
        let serviceType: NetworkProvider.RPCServiceType?

        var currentRetryCount: Int = 0
        var isExhausted: Bool = false

        init(
            operationName: String,
            connectId: UInt32,
            maxRetries: Int,
            uniqueKey: String,
            serviceType: NetworkProvider.RPCServiceType?
        ) {
            self.operationName = operationName
            self.connectId = connectId
            self.startTime = Date()
            self.maxRetries = maxRetries
            self.uniqueKey = uniqueKey
            self.serviceType = serviceType
        }
    }

    // MARK: - Initialization

    public init(configuration: RetryConfiguration = .default) {
        self.configuration = configuration

        // Start cleanup timer
        startCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    // MARK: - Execute with Retry

    /// Executes an RPC operation with comprehensive retry logic
    /// Migrated from: ExecuteRpcOperationAsync()
    public func executeRPCOperation<T>(
        operationName: String,
        connectId: UInt32,
        serviceType: NetworkProvider.RPCServiceType? = nil,
        maxRetries: Int? = nil,
        operation: @escaping (Int) async throws -> Result<T, NetworkFailure>
    ) async -> Result<T, NetworkFailure> {

        let actualMaxRetries = maxRetries ?? configuration.maxRetries

        // Check global exhaustion
        if await isGloballyExhausted() {
            Log.info("[RetryStrategy] 🚫 BLOCKED: Cannot start '\(operationName)' - system globally exhausted")
            return .failure(NetworkFailure(
                type: .dataCenterNotResponding,
                message: "All operations exhausted, manual retry required",
                shouldRetry: false
            ))
        }

        Log.info("[RetryStrategy] 🚀 EXECUTE: Starting '\(operationName)' on connectId \(connectId)")

        let operationKey = createOperationKey(operationName: operationName, connectId: connectId)
        let retryDelays = getOrCreateRetryDelays(maxRetries: actualMaxRetries)

        var lastResult: Result<T, NetworkFailure>?

        for attempt in 1...actualMaxRetries {
            do {
                // Execute operation with timeout
                let result = try await withTimeout(seconds: configuration.timeoutPerAttempt) {
                    await operation(attempt)
                }

                // Check result
                switch result {
                case .success:
                    if attempt > 1 {
                        Log.info("[RetryStrategy] ✅ SUCCESS: '\(operationName)' succeeded on attempt \(attempt)")
                    }
                    stopTrackingOperation(key: operationKey, reason: "Completed successfully")
                    return result

                case .failure(let networkFailure):
                    lastResult = result

                    // Check if we should retry
                    guard shouldRetry(failure: networkFailure) else {
                        Log.warning("[RetryStrategy] ⛔ NO RETRY: '\(operationName)' - non-retryable error")
                        stopTrackingOperation(key: operationKey, reason: "Non-retryable error")
                        return result
                    }

                    // Track retry attempt
                    if attempt == 1 {
                        startTrackingOperation(
                            operationName: operationName,
                            connectId: connectId,
                            maxRetries: actualMaxRetries,
                            operationKey: operationKey,
                            serviceType: serviceType
                        )
                    } else {
                        updateOperationRetryCount(key: operationKey, count: attempt)
                    }

                    // Check if retries exhausted
                    if attempt >= actualMaxRetries {
                        Log.warning("[RetryStrategy] 🔴 EXHAUSTED: '\(operationName)' after \(attempt) attempts")
                        markOperationAsExhausted(key: operationKey)

                        // Check if all operations are exhausted
                        if await isGloballyExhausted() {
                            Log.warning("[RetryStrategy] 🔴 ALL EXHAUSTED: All operations exhausted")
                            // Notify UI to show retry button (would integrate with event system)
                        }

                        return result
                    }

                    // Calculate delay
                    let delayIndex = min(attempt - 1, retryDelays.count - 1)
                    let delay = retryDelays[delayIndex]

                    Log.info("[RetryStrategy] 🔄 RETRY: '\(operationName)' attempt \(attempt)/\(actualMaxRetries), delay: \(String(format: "%.2f", delay))s")

                    // Wait before retry
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

            } catch {
                // Timeout or cancellation
                Log.warning("[RetryStrategy] ⏰ ERROR: '\(operationName)' attempt \(attempt) - \(error.localizedDescription)")

                if attempt >= actualMaxRetries {
                    markOperationAsExhausted(key: operationKey)
                    return .failure(NetworkFailure(
                        type: .timeout,
                        message: "Operation timed out after \(actualMaxRetries) attempts",
                        shouldRetry: true
                    ))
                }

                // Retry on timeout
                let delayIndex = min(attempt - 1, retryDelays.count - 1)
                let delay = retryDelays[delayIndex]
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // Fallback (shouldn't reach here)
        return lastResult ?? .failure(NetworkFailure(
            type: .unknown,
            message: "Retry logic completed without result",
            shouldRetry: false
        ))
    }

    // MARK: - Manual Retry

    /// Clears all exhausted operations to allow fresh retry
    /// Migrated from: ClearExhaustedOperations()
    public func clearExhaustedOperations() {
        operationsLock.lock()
        defer { operationsLock.unlock() }

        let exhaustedKeys = activeOperations.filter { $0.value.isExhausted }.map { $0.key }

        for key in exhaustedKeys {
            activeOperations.removeValue(forKey: key)
        }

        if !exhaustedKeys.isEmpty {
            Log.info("[RetryStrategy] 🔄 CLEARED: Removed \(exhaustedKeys.count) exhausted operations for fresh retry")
        }
    }

    /// Marks connection as healthy, resetting exhaustion state
    /// Migrated from: MarkConnectionHealthy()
    public func markConnectionHealthy(connectId: UInt32) {
        operationsLock.lock()
        defer { operationsLock.unlock() }

        var resetCount = 0
        for (key, operation) in activeOperations where operation.connectId == connectId && operation.isExhausted {
            operation.isExhausted = false
            operation.currentRetryCount = 0
            activeOperations.removeValue(forKey: key)
            resetCount += 1
        }

        if resetCount > 0 {
            Log.info("[RetryStrategy] 🔄 CONNECTION HEALTHY: Reset \(resetCount) operations for connectId \(connectId)")
        }
    }

    // MARK: - Operation Tracking

    private func startTrackingOperation(
        operationName: String,
        connectId: UInt32,
        maxRetries: Int,
        operationKey: String,
        serviceType: NetworkProvider.RPCServiceType?
    ) {
        operationsLock.lock()
        defer { operationsLock.unlock() }

        // Cleanup if too many operations
        if activeOperations.count >= maxTrackedOperations {
            Log.warning("[RetryStrategy] ⚠️ Max tracked operations reached, cleaning up old operations")
            cleanupAbandonedOperationsInternal()
        }

        let operation = RetryOperationInfo(
            operationName: operationName,
            connectId: connectId,
            maxRetries: maxRetries,
            uniqueKey: operationKey,
            serviceType: serviceType
        )
        operation.currentRetryCount = 1

        activeOperations[operationKey] = operation

        Log.debug("[RetryStrategy] 🟡 TRACKING: '\(operationName)' on connectId \(connectId). Active: \(activeOperations.count)")
    }

    private func updateOperationRetryCount(key: String, count: Int) {
        operationsLock.lock()
        defer { operationsLock.unlock() }

        if let operation = activeOperations[key] {
            operation.currentRetryCount = count
            Log.debug("[RetryStrategy] 📊 UPDATE: Retry count \(count)/\(operation.maxRetries) for key \(key)")
        }
    }

    private func stopTrackingOperation(key: String, reason: String) {
        operationsLock.lock()
        defer { operationsLock.unlock() }

        if let operation = activeOperations.removeValue(forKey: key) {
            Log.debug("[RetryStrategy] 🟢 STOPPED: '\(operation.operationName)' on connectId \(operation.connectId) - \(reason). Remaining: \(activeOperations.count)")
        }
    }

    private func markOperationAsExhausted(key: String) {
        operationsLock.lock()
        defer { operationsLock.unlock() }

        if let operation = activeOperations[key] {
            operation.isExhausted = true
            Log.debug("[RetryStrategy] 🔴 EXHAUSTED: '\(operation.operationName)' on connectId \(operation.connectId)")
        }
    }

    // MARK: - Global Exhaustion Check

    private func isGloballyExhausted() async -> Bool {
        operationsLock.lock()
        defer { operationsLock.unlock() }

        guard !activeOperations.isEmpty else {
            return false
        }

        // Check if all tracked operations are exhausted
        let hasNonExhausted = activeOperations.values.contains { !$0.isExhausted }
        return !hasNonExhausted
    }

    // MARK: - Retry Decision

    private func shouldRetry(failure: NetworkFailure) -> Bool {
        return failure.shouldRetry
    }

    // MARK: - Retry Delays

    private func getOrCreateRetryDelays(maxRetries: Int) -> [TimeInterval] {
        let cacheKey = "delays_\(maxRetries)"

        if let cached = retryDelaysCache[cacheKey] {
            return cached
        }

        // Calculate delays with decorrelated jitter
        var delays: [TimeInterval] = []
        var currentDelay = configuration.initialDelay

        for _ in 0..<maxRetries {
            // Add jitter (±20%)
            let jitterFactor = Double.random(in: 0.8...1.2)
            let delayWithJitter = currentDelay * jitterFactor

            // Cap at max delay
            let finalDelay = min(delayWithJitter, configuration.maxDelay)
            delays.append(finalDelay)

            // Exponential increase
            currentDelay = min(currentDelay * 2.0, configuration.maxDelay)
        }

        retryDelaysCache[cacheKey] = delays
        return delays
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            self?.cleanupAbandonedOperations()
        }
    }

    private func cleanupAbandonedOperations() {
        operationsLock.lock()
        defer { operationsLock.unlock() }

        cleanupAbandonedOperationsInternal()
    }

    private func cleanupAbandonedOperationsInternal() {
        let cutoff = Date().addingTimeInterval(-operationTimeout)
        let abandoned = activeOperations.filter { $0.value.startTime < cutoff }

        for (key, _) in abandoned {
            activeOperations.removeValue(forKey: key)
        }

        if !abandoned.isEmpty {
            Log.info("[RetryStrategy] 🧹 CLEANUP: Removed \(abandoned.count) abandoned operations")
        }
    }

    // MARK: - Helpers

    private func createOperationKey(operationName: String, connectId: UInt32) -> String {
        return "\(operationName)_\(connectId)_\(Date().timeIntervalSince1970)_\(UUID().uuidString)"
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Start the operation
            group.addTask {
                try await operation()
            }

            // Start the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NetworkError.timeout(seconds)
            }

            // Return the first one to complete
            let result = try await group.next()!

            // Cancel the other task
            group.cancelAll()

            return result
        }
    }
}
