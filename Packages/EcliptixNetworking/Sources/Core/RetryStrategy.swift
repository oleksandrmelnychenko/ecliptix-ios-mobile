import EcliptixCore
import Foundation

public actor RetryStrategy {
    private let configuration: RetryConfiguration
    private let maxTrackedOperations: Int = 1000
    private let cleanupInterval: TimeInterval = 300
    private let operationTimeout: TimeInterval = 600
    private var activeOperations: [String: RetryOperationInfo] = [:]
    private var retryDelaysCache: [String: [TimeInterval]] = [:]

    private weak var connectionRecoveryDelegate: ConnectionRecoveryDelegate?
    private var cleanupTask: Task<Void, Never>?

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

    public init(configuration: RetryConfiguration = .default) {
        self.configuration = configuration
    }

    public func setConnectionRecoveryDelegate(_ delegate: ConnectionRecoveryDelegate) {
        self.connectionRecoveryDelegate = delegate
    }

    public func startCleanup() {
        guard cleanupTask == nil else { return }
        cleanupTask = Task { [weak self] in
            await self?.runCleanupLoop()
        }
    }

    deinit {
        cleanupTask?.cancel()
    }

    public func executeRPCOperation<T: Sendable>(
        operationName: String,
        connectId: UInt32,
        serviceType: NetworkProvider.RPCServiceType? = nil,
        maxRetries: Int? = nil,
        operation: @escaping @Sendable (Int) async throws -> Result<T, NetworkFailure>
    ) async -> Result<T, NetworkFailure> {

        let actualMaxRetries = maxRetries ?? configuration.maxRetries

        if isGloballyExhausted() {
            Log.info("[RetryStrategy]  BLOCKED: Cannot start '\(operationName)' - system globally exhausted")
            return .failure(NetworkFailure(
                type: .dataCenterNotResponding,
                message: "All operations exhausted, manual retry required"
            ))
        }

        Log.info("[RetryStrategy] [START] EXECUTE: Starting '\(operationName)' on connectId \(connectId)")

        let operationKey = createOperationKey(operationName: operationName, connectId: connectId)
        let retryDelays = getOrCreateRetryDelays(maxRetries: actualMaxRetries)

        var lastResult: Result<T, NetworkFailure>?

        for attempt in 1...actualMaxRetries {
            do {

                let result = try await withTimeout(seconds: configuration.timeoutPerAttempt) {
                    try await operation(attempt)
                }

                switch result {
                case .success:
                    if attempt > 1 {
                        Log.info("[RetryStrategy] [OK] SUCCESS: '\(operationName)' succeeded on attempt \(attempt)")
                    }
                    stopTrackingOperation(key: operationKey, reason: "Completed successfully")
                    return result

                case .failure(let networkFailure):
                    lastResult = result

                    guard shouldRetry(failure: networkFailure) else {
                        Log.warning("[RetryStrategy]  NO RETRY: '\(operationName)' - non-retryable error")
                        stopTrackingOperation(key: operationKey, reason: "Non-retryable error")
                        return result
                    }

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

                    if await shouldTriggerConnectionRecovery(failure: networkFailure) {
                        Log.info("[RetryStrategy] [DEBUG] RECOVERY: Triggering connection recovery for connectId \(connectId)")
                        await attemptConnectionRecovery(connectId: connectId)
                    }

                    if attempt >= actualMaxRetries {
                        Log.warning("[RetryStrategy] [ERROR] EXHAUSTED: '\(operationName)' after \(attempt) attempts")
                        markOperationAsExhausted(key: operationKey)

                        if isGloballyExhausted() {
                            Log.warning("[RetryStrategy] [ERROR] ALL EXHAUSTED: All operations exhausted")

                        }

                        return result
                    }

                    let delayIndex = min(attempt - 1, retryDelays.count - 1)
                    let delay = retryDelays[delayIndex]

                    Log.info("[RetryStrategy]  RETRY: '\(operationName)' attempt \(attempt)/\(actualMaxRetries), delay: \(String(format: "%.2f", delay))s")

                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

            } catch {

                Log.warning("[RetryStrategy] ⏰ ERROR: '\(operationName)' attempt \(attempt) - \(error.localizedDescription)")

                Log.info("[RetryStrategy] [DEBUG] RECOVERY: Timeout detected, triggering connection recovery for connectId \(connectId)")
                await attemptConnectionRecovery(connectId: connectId)

                if attempt >= actualMaxRetries {
                    markOperationAsExhausted(key: operationKey)
                    return .failure(NetworkFailure(
                        type: .timeout,
                        message: "Operation timed out after \(actualMaxRetries) attempts"
                    ))
                }

                let delayIndex = min(attempt - 1, retryDelays.count - 1)
                let delay = retryDelays[delayIndex]
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        return lastResult ?? .failure(NetworkFailure(
            type: .unknown,
            message: "Retry logic completed without result"
        ))
    }

    public func clearExhaustedOperations() {
        let exhaustedKeys = activeOperations.filter { $0.value.isExhausted }.map { $0.key }

        for key in exhaustedKeys {
            activeOperations.removeValue(forKey: key)
        }

        if !exhaustedKeys.isEmpty {
            Log.info("[RetryStrategy]  CLEARED: Removed \(exhaustedKeys.count) exhausted operations for fresh retry")
        }
    }

    public func markConnectionHealthy(connectId: UInt32) {
        var resetCount = 0
        for (key, operation) in activeOperations where operation.connectId == connectId && operation.isExhausted {
            operation.isExhausted = false
            operation.currentRetryCount = 0
            activeOperations.removeValue(forKey: key)
            resetCount += 1
        }

        if resetCount > 0 {
            Log.info("[RetryStrategy]  CONNECTION HEALTHY: Reset \(resetCount) operations for connectId \(connectId)")
        }
    }

    private func startTrackingOperation(
        operationName: String,
        connectId: UInt32,
        maxRetries: Int,
        operationKey: String,
        serviceType: NetworkProvider.RPCServiceType?
    ) {

        if activeOperations.count >= maxTrackedOperations {
            Log.warning("[RetryStrategy] [WARNING] Max tracked operations reached, cleaning up old operations")
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

        Log.debug("[RetryStrategy]  TRACKING: '\(operationName)' on connectId \(connectId). Active: \(activeOperations.count)")
    }

    private func updateOperationRetryCount(key: String, count: Int) {
        if let operation = activeOperations[key] {
            operation.currentRetryCount = count
            Log.debug("[RetryStrategy]  UPDATE: Retry count \(count)/\(operation.maxRetries) for key \(key)")
        }
    }

    private func stopTrackingOperation(key: String, reason: String) {
        if let operation = activeOperations.removeValue(forKey: key) {
            Log.debug("[RetryStrategy]  STOPPED: '\(operation.operationName)' on connectId \(operation.connectId) - \(reason). Remaining: \(activeOperations.count)")
        }
    }

    private func markOperationAsExhausted(key: String) {
        if let operation = activeOperations[key] {
            operation.isExhausted = true
            Log.debug("[RetryStrategy] [ERROR] EXHAUSTED: '\(operation.operationName)' on connectId \(operation.connectId)")
        }
    }

    private func isGloballyExhausted() -> Bool {
        guard !activeOperations.isEmpty else {
            return false
        }

        let hasNonExhausted = activeOperations.values.contains { !$0.isExhausted }
        return !hasNonExhausted
    }

    private func shouldRetry(failure: NetworkFailure) -> Bool {
        return failure.shouldRetry
    }

    private func getOrCreateRetryDelays(maxRetries: Int) -> [TimeInterval] {
        let cacheKey = "delays_\(maxRetries)"

        if let cached = retryDelaysCache[cacheKey] {
            return cached
        }

        var delays: [TimeInterval] = []
        var currentDelay = configuration.initialDelay

        for _ in 0..<maxRetries {

            let jitterFactor = Double.random(in: 0.8...1.2)
            let delayWithJitter = currentDelay * jitterFactor

            let finalDelay = min(delayWithJitter, configuration.maxDelay)
            delays.append(finalDelay)

            currentDelay = min(currentDelay * 2.0, configuration.maxDelay)
        }

        retryDelaysCache[cacheKey] = delays
        return delays
    }

    private func runCleanupLoop() async {
        while !Task.isCancelled {

            try? await Task.sleep(nanoseconds: UInt64(cleanupInterval * 1_000_000_000))

            await cleanupAbandonedOperations()
        }
    }

    private func cleanupAbandonedOperations() async {
        cleanupAbandonedOperationsInternal()
    }

    private func cleanupAbandonedOperationsInternal() {
        let cutoff = Date().addingTimeInterval(-operationTimeout)
        let abandoned = activeOperations.filter { $0.value.startTime < cutoff }

        for (key, _) in abandoned {
            activeOperations.removeValue(forKey: key)
        }

        if !abandoned.isEmpty {
            Log.info("[RetryStrategy]  CLEANUP: Removed \(abandoned.count) abandoned operations")
        }
    }

    private func createOperationKey(operationName: String, connectId: UInt32) -> String {
        return "\(operationName)_\(connectId)_\(Date().timeIntervalSince1970)_\(UUID().uuidString)"
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NetworkError.timeout(seconds)
            }

            guard let result = try await group.next() else {
                throw NetworkError.cancelled
            }

            group.cancelAll()

            return result
        }
    }

    private func shouldTriggerConnectionRecovery(failure: NetworkFailure) async -> Bool {

        switch failure.type {
        case .protocolStateMismatch, .handshakeFailed:

            return true

        case .timeout, .connectionFailed, .unavailable:

            return true

        case .unauthenticated, .permissionDenied:

            if let delegate = connectionRecoveryDelegate {
                return await delegate.shouldRecoverConnection(for: failure)
            }
            return false

        default:

            if let delegate = connectionRecoveryDelegate {
                return await delegate.shouldRecoverConnection(for: failure)
            }
            return false
        }
    }

    private func attemptConnectionRecovery(connectId: UInt32) async {
        guard let delegate = connectionRecoveryDelegate else {
            Log.debug("[RetryStrategy] No connection recovery delegate available")
            return
        }

        await delegate.beginConnectionRecovery()

        let isHealthy = await delegate.isConnectionHealthy(connectId: connectId)
        if isHealthy {
            Log.debug("[RetryStrategy] [OK] Connection \(connectId) is already healthy")
            return
        }

        Log.info("[RetryStrategy] [DEBUG] Attempting to restore connection \(connectId)")

        let restored = await delegate.tryRestoreConnection(connectId: connectId)

        if restored {
            Log.info("[RetryStrategy] [OK] Successfully restored connection \(connectId)")

            markConnectionHealthy(connectId: connectId)
        } else {
            Log.warning("[RetryStrategy] [WARNING] Failed to restore connection \(connectId)")
        }
    }
}

public protocol ConnectionRecoveryDelegate: AnyObject, Sendable {

    func shouldRecoverConnection(for failure: NetworkFailure) async -> Bool

    func beginConnectionRecovery() async

    func isConnectionHealthy(connectId: UInt32) async -> Bool

    func tryRestoreConnection(connectId: UInt32) async -> Bool
}
