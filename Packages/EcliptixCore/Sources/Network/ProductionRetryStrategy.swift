@preconcurrency import Combine
import Foundation


private struct RetryOperationInfo {
    let operationId: UUID
    let operationName: String
    let connectId: UInt32?
    let serviceType: String?
    let startTime: Date
    var currentAttempt: Int
    var isExhausted: Bool
    var lastFailure: NetworkFailure?
    let delays: [TimeInterval]

    var isActive: Bool {
        Date().timeIntervalSince(startTime) < 600 // 10 minutes
    }
}


public protocol ConnectionRecoveryDelegate: Sendable {
    func requestConnectionRecovery(
        reason: String,
        failure: NetworkFailure?,
        connectId: UInt32?
    ) async
}


public actor ProductionRetryStrategy {


    private let configuration: RetryStrategyConfiguration
    private let messageBus: MessageBus
    private var connectionRecoveryDelegate: ConnectionRecoveryDelegate?

    private var activeOperations: [UUID: RetryOperationInfo] = [:]

    private var isGloballyExhausted: Bool = false

    private var manualRetryRequested: Bool = false

    private var cleanupTask: Task<Void, Never>?

    private var manualRetrySubscription: AnyCancellable?


    public init(
        configuration: RetryStrategyConfiguration = .default,
        messageBus: MessageBus = GlobalMessageBus,
        connectionRecoveryDelegate: ConnectionRecoveryDelegate? = nil
    ) {
        self.configuration = configuration
        self.messageBus = messageBus
        self.connectionRecoveryDelegate = connectionRecoveryDelegate

        Log.info("[ProductionRetryStrategy] Initialized with config: maxRetries=\(configuration.maxRetries)")

        Task { [weak self] in
            await self?.startCleanupTimer()
            await self?.setupManualRetrySubscription()
        }
    }

    deinit {
        cleanupTask?.cancel()
        manualRetrySubscription?.cancel()
    }


    public func executeRPCOperation<T>(
        operationName: String,
        connectId: UInt32? = nil,
        serviceType: String? = nil,
        maxRetries: Int? = nil,
        bypassExhaustion: Bool = false,
        operation: @escaping (Int) async throws -> T
    ) async -> Result<T, NetworkFailure> {

        let operationId = UUID()
        let actualMaxRetries = maxRetries ?? configuration.maxRetries

        Log.debug("[ProductionRetryStrategy] Starting operation '\(operationName)' [ID: \(operationId)]")

        if !bypassExhaustion && isGloballyExhausted {
            Log.error("[ProductionRetryStrategy] Globally exhausted - rejecting '\(operationName)'")
            return .failure(NetworkFailure.dataCenterNotResponding("All operations exhausted, manual retry required"))
        }

        let delays: [TimeInterval] = (0..<actualMaxRetries).map { configuration.calculateDelay(for: $0) }

        let operationInfo = RetryOperationInfo(
            operationId: operationId,
            operationName: operationName,
            connectId: connectId,
            serviceType: serviceType,
            startTime: Date(),
            currentAttempt: 0,
            isExhausted: false,
            lastFailure: nil,
            delays: delays
        )

        activeOperations[operationId] = operationInfo

        await messageBus.publish(OperationStartedMessage(
            operationId: operationId,
            operationName: operationName,
            connectId: connectId
        ))

        let result = await executeWithRetries(
            operationId: operationId,
            operationInfo: operationInfo,
            maxRetries: actualMaxRetries,
            operation: operation
        )

        activeOperations.removeValue(forKey: operationId)

        let duration = Date().timeIntervalSince(operationInfo.startTime)
        await messageBus.publish(OperationCompletedMessage(
            operationId: operationId,
            operationName: operationName,
            success: result.isSuccess,
            error: result.failureValue,
            duration: duration
        ))

        return result
    }

    public func executeManualRetryRPCOperation<T>(
        operationName: String,
        connectId: UInt32? = nil,
        serviceType: String? = nil,
        maxRetries: Int? = nil,
        operation: @escaping (Int) async throws -> T
    ) async -> Result<T, NetworkFailure> {

        Log.info("[ProductionRetryStrategy] Manual retry for '\(operationName)'")

        if isGloballyExhausted {
            isGloballyExhausted = false
            Log.info("[ProductionRetryStrategy] Global exhaustion reset by manual retry")
        }

        return await executeRPCOperation(
            operationName: operationName,
            connectId: connectId,
            serviceType: serviceType,
            maxRetries: maxRetries,
            bypassExhaustion: true,
            operation: operation
        )
    }


    private func executeWithRetries<T>(
        operationId: UUID,
        operationInfo: RetryOperationInfo,
        maxRetries: Int,
        operation: @escaping (Int) async throws -> T
    ) async -> Result<T, NetworkFailure> {

        var info = operationInfo

        for attempt in 0..<maxRetries {
            info.currentAttempt = attempt

            Log.debug("[ProductionRetryStrategy] [\(info.operationName)] Attempt \(attempt + 1)/\(maxRetries)")

            if attempt > 0, let failure = info.lastFailure {
                let delay = info.delays[attempt]
                await publishRecoveringIntent(
                    failure: failure,
                    connectId: info.connectId,
                    retryAttempt: attempt + 1,
                    backoff: delay
                )
            }

            do {
                let result = try await operation(attempt)

                Log.info("[ProductionRetryStrategy] [\(info.operationName)] ✓ SUCCESS")

                onOperationSuccess(operationId: operationId)

                return .success(result)

            } catch let error as NetworkFailure {

                info.lastFailure = error
                activeOperations[operationId] = info

                Log.warning("[ProductionRetryStrategy] [\(info.operationName)] Attempt \(attempt + 1) failed: \(error.type)")

                if !error.shouldRetry {
                    Log.error("[ProductionRetryStrategy] [\(info.operationName)] Non-retryable failure: \(error.type)")
                    markOperationExhausted(operationId: operationId, failure: error)
                    return .failure(error)
                }

                let requiresRecovery = [
                    .protocolStateMismatch,
                    .handshakeFailed,
                    .connectionFailed,
                    .unavailable,
                    .timeout
                ].contains(error.type)

                if requiresRecovery {
                    Log.warning("[ProductionRetryStrategy] [\(info.operationName)] Connection recovery required")
                    await triggerConnectionRecovery(failure: error, connectId: info.connectId)
                }

                if attempt >= maxRetries - 1 {
                    Log.error("[ProductionRetryStrategy] [\(info.operationName)] Max retries reached")
                    markOperationExhausted(operationId: operationId, failure: error)
                    return .failure(error)
                }

                let delay = info.delays[attempt]
                Log.debug("[ProductionRetryStrategy] [\(info.operationName)] Backing off for \(String(format: "%.2fs", delay))")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            } catch {
                let networkFailure = NetworkFailure.unknown(
                    error.localizedDescription,
                    underlyingError: error
                )
                Log.error("[ProductionRetryStrategy] [\(info.operationName)] Unexpected error: \(error)")
                markOperationExhausted(operationId: operationId, failure: networkFailure)
                return .failure(networkFailure)
            }
        }

        let failure = info.lastFailure ?? .unknown("Max retries exceeded")
        markOperationExhausted(operationId: operationId, failure: failure)
        return .failure(failure)
    }


    private func onOperationSuccess(operationId: UUID) {
        if var info = activeOperations[operationId] {
            info.isExhausted = false
            info.lastFailure = nil
            activeOperations[operationId] = info
        }

        let allExhausted = activeOperations.values.allSatisfy { $0.isExhausted }
        if !allExhausted && isGloballyExhausted {
            isGloballyExhausted = false
            Log.info("[ProductionRetryStrategy] Global exhaustion cleared after success")
        }
    }

    private func markOperationExhausted(operationId: UUID, failure: NetworkFailure) {
        if var info = activeOperations[operationId] {
            info.isExhausted = true
            info.lastFailure = failure
            activeOperations[operationId] = info

            Log.error("[ProductionRetryStrategy] [\(info.operationName)] Operation exhausted after \(info.currentAttempt + 1) attempts")

            Task {
                await messageBus.publish(RetriesExhaustedMessage(
                    connectId: info.connectId,
                    operationName: info.operationName,
                    totalAttempts: info.currentAttempt + 1,
                    failure: failure
                ))
            }

            checkGlobalExhaustion()
        }
    }

    private func checkGlobalExhaustion() {
        let activeOps = activeOperations.values.filter { $0.isActive }
        let allExhausted = !activeOps.isEmpty && activeOps.allSatisfy { $0.isExhausted }

        if allExhausted && !isGloballyExhausted {
            isGloballyExhausted = true
            Log.error("[ProductionRetryStrategy] 🔴 GLOBALLY EXHAUSTED - manual retry required")
        }
    }


    private func triggerConnectionRecovery(failure: NetworkFailure, connectId: UInt32?) async {
        Log.warning("[ProductionRetryStrategy] Triggering connection recovery")

        await messageBus.publish(ConnectionRecoveryRequestedMessage(
            reason: .protocolStateMismatch,
            connectId: connectId,
            failure: failure
        ))

        if let delegate = connectionRecoveryDelegate {
            await delegate.requestConnectionRecovery(
                reason: "Protocol state mismatch",
                failure: failure,
                connectId: connectId
            )
        }
    }


    private func publishRecoveringIntent(
        failure: NetworkFailure,
        connectId: UInt32?,
        retryAttempt: Int,
        backoff: TimeInterval
    ) async {
        await messageBus.publish(ConnectivityIntentMessage(
            intent: .recovering(
                failure: failure,
                connectId: connectId,
                retryAttempt: retryAttempt,
                backoff: backoff
            )
        ))
    }

    private func setupManualRetrySubscription() {
        manualRetrySubscription = AnyCancellable {
            Task { [weak self] in
                guard let self = self else { return }

                let subscription = await self.messageBus.subscribe(
                    lifetime: .strong
                ) { [weak self] (message: ManualRetryRequestedMessage) in
                    await self?.handleManualRetryRequest(message)
                }

                _ = subscription
            }
        }
    }

    private func handleManualRetryRequest(_ message: ManualRetryRequestedMessage) async {
        Log.info("[ProductionRetryStrategy] Manual retry requested from \(message.source)")

        manualRetryRequested = true
        isGloballyExhausted = false

        for (id, var info) in activeOperations {
            info.isExhausted = false
            activeOperations[id] = info
        }

        Log.info("[ProductionRetryStrategy] All operations reset for manual retry")
    }


    private func startCleanupTimer() {
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // 5 minutes

                await performCleanup()
            }
        }
    }

    private func performCleanup() async {
        let initialCount = activeOperations.count

        activeOperations = activeOperations.filter { _, info in
            info.isActive
        }

        let removedCount = initialCount - activeOperations.count
        if removedCount > 0 {
            Log.debug("[ProductionRetryStrategy] Cleaned up \(removedCount) stale operations")
        }
    }


    public func isOperationActive(_ operationId: UUID) -> Bool {
        activeOperations[operationId] != nil
    }

    public func getActiveOperationCount() -> Int {
        activeOperations.count
    }

    public func isExhausted() -> Bool {
        isGloballyExhausted
    }

    public func setConnectionRecoveryDelegate(_ delegate: ConnectionRecoveryDelegate?) {
        self.connectionRecoveryDelegate = delegate
    }
}


private extension Result {

    var failureValue: Failure? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}
