import Combine
import EcliptixCore
import EcliptixSecurity
import Foundation

@MainActor
public final class NetworkProvider {

    internal let connectionManager: ProtocolConnectionManager
    internal let channelManager: GRPCChannelManager
    internal let connectivityService: ConnectivityService
    internal let retryStrategy: RetryStrategy
    internal let pendingRequestManager: PendingRequestManager
    internal let circuitBreaker: CircuitBreaker
    internal let healthMonitor: ConnectionHealthMonitor

    internal var activeRequests: [String: Task<Void, Never>] = [:]

    internal var isInOutage: Bool = false
    internal var outageRecoveryContinuation: CheckedContinuation<Void, Never>?

    internal var applicationInstanceSettings: ApplicationInstanceSettings?

    internal var isShutdown: Bool = false

    private var backgroundTasks: [Task<Void, Never>] = []

    public enum ConnectionMode {
        case authenticated
        case unauthenticated
    }

    internal var connectionMode: ConnectionMode = .unauthenticated

    public enum RPCServiceType: String, Sendable {
        case registrationInit
        case registrationComplete
        case signInInit
        case signInComplete
        case logout
        case validateMobileNumber
        case checkMobileAvailability
        case verifyOtp
        case registerDevice
        case updateDeviceInfo
        case getDeviceStatus
        case restoreSecureChannel
        case establishSecureChannel
        case sendMessage
    }

    public init(
        connectionManager: ProtocolConnectionManager = ProtocolConnectionManager(),
        channelManager: GRPCChannelManager,
        connectivityService: ConnectivityService? = nil,
        retryConfiguration: RetryConfiguration = .default,
        circuitBreakerConfiguration: CircuitBreakerConfiguration = .default,
        healthMonitorConfiguration: HealthMonitorConfiguration = .default
    ) {
        self.connectionManager = connectionManager
        self.channelManager = channelManager

        let connectivity = connectivityService ?? DefaultConnectivityService()
        self.connectivityService = connectivity

        self.retryStrategy = RetryStrategy(configuration: retryConfiguration)

        self.pendingRequestManager = PendingRequestManager()

        self.circuitBreaker = CircuitBreaker(configuration: circuitBreakerConfiguration)
        self.healthMonitor = ConnectionHealthMonitor(configuration: healthMonitorConfiguration)

        if let defaultConnectivity = connectivity as? DefaultConnectivityService {
            defaultConnectivity.startMonitoring()
        }

        let networkChangesTask = Task {
            await self.subscribeToNetworkChanges()
        }
        backgroundTasks.append(networkChangesTask)

        let healthChangesTask = Task {
            await self.subscribeToHealthChanges()
        }
        backgroundTasks.append(healthChangesTask)

        let manualRetryTask = Task {
            await self.subscribeToManualRetryEvents()
        }
        backgroundTasks.append(manualRetryTask)
    }

    deinit {
        for task in backgroundTasks {
            task.cancel()
        }
        backgroundTasks.removeAll()
    }

    private func subscribeToHealthChanges() async {
        for await health in healthMonitor.healthStatusPublisher.values {

            if health.status == .critical {

                Log.warning("[NetworkProvider] [WARNING] Connection \(health.connectId) is critical - considering circuit breaker")
            } else if health.status == .healthy {

                circuitBreaker.resetConnection(health.connectId)
                await retryStrategy.markConnectionHealthy(connectId: health.connectId)
                Log.info("[NetworkProvider] [OK] Connection \(health.connectId) is healthy - reset circuit")
            }
        }
    }

    private func subscribeToNetworkChanges() async {
        for await snapshot in connectivityService.connectivityStream.values {
            switch snapshot.status {
            case .connected:

                if isInOutage {
                    exitOutage()
                }

            case .disconnected, .unavailable, .shuttingDown:

                if !isInOutage {
                    enterOutage()
                }

            case .retriesExhausted:

                Log.warning("[NetworkProvider]  Network retries exhausted")
                if !isInOutage {
                    enterOutage()
                }

            case .connecting, .recovering:

                break
            }
        }
    }

    private func subscribeToManualRetryEvents() async {
        _ = connectivityService.onManualRetryRequested { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                Log.info("[NetworkProvider]  Manual retry requested")

                if self.isInOutage {
                    self.exitOutage()
                }

                if let connectId = event.connectId {
                    Log.debug("[NetworkProvider] Retrying for connection \(connectId)")
                }
            }
        }
    }

    private func enterOutage() {

        guard !isInOutage else { return }

        isInOutage = true
        Log.warning("[NetworkProvider] Entered network outage mode")
    }

    private func exitOutage() {
        let continuation = outageRecoveryContinuation
        outageRecoveryContinuation = nil
        isInOutage = false

        Log.info("[NetworkProvider] [OK] Exited network outage mode")

        continuation?.resume()

        Log.debug("[NetworkProvider] Pending requests will auto-retry via ConnectivityService")
    }

    private func waitForOutageRecovery() async throws {
        guard isInOutage else {
            return
        }

        Log.info("[NetworkProvider] Waiting for outage recovery...")

        await withCheckedContinuation { continuation in
            outageRecoveryContinuation = continuation

            if !isInOutage {
                let storedContinuation = outageRecoveryContinuation
                outageRecoveryContinuation = nil
                storedContinuation?.resume()
            }
        }
    }

    private func generateRequestKey(connectId: UInt32, serviceType: RPCServiceType, plainBuffer: Data) -> String {

        if serviceType == .signInInit || serviceType == .signInComplete {
            return "\(connectId)_\(serviceType.rawValue)_auth_operation"
        }

        let bytesToHash = min(plainBuffer.count, 32)
        let prefix = plainBuffer.prefix(bytesToHash)
        let hexString = prefix.map { String(format: "%02x", $0) }.joined()

        return "\(connectId)_\(serviceType.rawValue)_\(hexString)"
    }

    private func canServiceTypeBeDuplicated(_ serviceType: RPCServiceType) -> Bool {

        switch serviceType {
        case .sendMessage, .updateDeviceInfo:
            return true
        default:
            return false
        }
    }

    public func setConnectionMode(_ mode: ConnectionMode) {
        self.connectionMode = mode
        switch mode {
        case .authenticated:
            Log.info("[NetworkProvider]  Connection mode set to AUTHENTICATED (E2E encrypted)")
        case .unauthenticated:
            Log.info("[NetworkProvider] [WARNING] Connection mode set to UNAUTHENTICATED (plain connection)")
        }
    }

    public func initiateProtocolConnection(connectId: UInt32, identityKeys: IdentityKeys) async {
        await connectionManager.addConnection(connectId: connectId, identityKeys: identityKeys)
        Log.info("[NetworkProvider] Initiated protocol connection \(connectId)")

        if let defaultConnectivity = connectivityService as? DefaultConnectivityService {
            defaultConnectivity.notifyServerConnecting(connectId: connectId)
        }
    }

    public func cleanupProtocolConnection(_ connectId: UInt32) async {
        await connectionManager.removeConnection(connectId)
        Log.info("[NetworkProvider] Cleaned up protocol connection \(connectId)")
    }

    public func setApplicationInstanceSettings(_ settings: ApplicationInstanceSettings) {
        self.applicationInstanceSettings = settings
        Log.info("[NetworkProvider] Application instance settings configured")
    }

    public func executeUnaryRequest(
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        allowDuplicates: Bool = false,
        waitForRecovery: Bool = true,
        onCompleted: @escaping (Data) async throws -> Void
    ) async -> Result<Void, NetworkFailure> {

        let requestKey = generateRequestKey(connectId: connectId, serviceType: serviceType, plainBuffer: plainBuffer)

        let shouldAllowDuplicates = allowDuplicates || canServiceTypeBeDuplicated(serviceType)

        if !shouldAllowDuplicates {
            if activeRequests[requestKey] != nil {
                Log.warning("[NetworkProvider] Duplicate request rejected: \(requestKey)")
                return .failure(NetworkFailure(
                    type: .invalidRequest,
                    message: "Duplicate request rejected",
                ))
            }

            let placeholder = Task<Void, Never> { }
            activeRequests[requestKey] = placeholder
        }

        return await withTaskCancellationHandler {
            await executeRequestInternal(
                connectId: connectId,
                serviceType: serviceType,
                plainBuffer: plainBuffer,
                requestKey: requestKey,
                shouldAllowDuplicates: shouldAllowDuplicates,
                waitForRecovery: waitForRecovery,
                onCompleted: onCompleted
            )
        } onCancel: {

            if !shouldAllowDuplicates {
                Task { @MainActor in
                    activeRequests.removeValue(forKey: requestKey)
                }
            }
        }
    }

    public func executeWithRetry<T: Sendable>(
        operationName: String,
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        allowDuplicates: Bool = false,
        waitForRecovery: Bool = true,
        maxRetries: Int? = nil,
        onCompleted: @escaping @Sendable (Data) async throws -> T
    ) async -> Result<T, NetworkFailure> {

        let result = await retryStrategy.executeRPCOperation(
            operationName: operationName,
            connectId: connectId,
            serviceType: serviceType,
            maxRetries: maxRetries
        ) { attempt in
            Log.debug("[NetworkProvider] Executing '\(operationName)' attempt \(attempt)")

            var capturedResult: T?
            let requestResult = await self.executeUnaryRequest(
                connectId: connectId,
                serviceType: serviceType,
                plainBuffer: plainBuffer,
                allowDuplicates: allowDuplicates,
                waitForRecovery: waitForRecovery
            ) { responseData in
                capturedResult = try await onCompleted(responseData)
            }

            switch requestResult {
            case .success:
                if let value = capturedResult {
                    return .success(value)
                } else {
                    return .failure(NetworkFailure(
                        type: .unknown,
                        message: "Response processing failed - no result captured"
                    ))
                }
            case .failure(let error):
                return .failure(error)
            }
        }

        return result
    }

    private func executeRequestInternal(
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        requestKey: String,
        shouldAllowDuplicates: Bool,
        waitForRecovery: Bool,
        onCompleted: @escaping (Data) async throws -> Void
    ) async -> Result<Void, NetworkFailure> {

        let requestStartTime = Date()

        defer {
            if !shouldAllowDuplicates {
                activeRequests.removeValue(forKey: requestKey)
            }
        }

        let circuitResult = await circuitBreaker.execute(
            connectId: connectId,
            operationName: serviceType.rawValue
        ) {
            await self.executeRequestWithProtocol(
                connectId: connectId,
                serviceType: serviceType,
                plainBuffer: plainBuffer,
                requestKey: requestKey,
                waitForRecovery: waitForRecovery,
                onCompleted: onCompleted
            )
        }

        let latency = Date().timeIntervalSince(requestStartTime)
        switch circuitResult {
        case .success:
            healthMonitor.recordSuccess(connectId: connectId, latency: latency)
        case .failure(let error):
            healthMonitor.recordFailure(connectId: connectId, error: error)
        }

        return circuitResult
    }

    private func executeRequestWithProtocol(
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        requestKey: String,
        waitForRecovery: Bool,
        onCompleted: @escaping (Data) async throws -> Void
    ) async -> Result<Void, NetworkFailure> {

        if waitForRecovery {
            do {
                try await waitForOutageRecovery()
            } catch {
                return .failure(NetworkFailure(
                    type: .operationCancelled,
                    message: "Request cancelled during outage recovery",
                ))
            }
        }

        switch connectionMode {
        case .authenticated:
            return await executeAuthenticatedRequest(
                connectId: connectId,
                serviceType: serviceType,
                plainBuffer: plainBuffer,
                onCompleted: onCompleted
            )

        case .unauthenticated:
            return await executeUnauthenticatedRequest(
                connectId: connectId,
                serviceType: serviceType,
                plainBuffer: plainBuffer,
                onCompleted: onCompleted
            )
        }
    }

    private func executeAuthenticatedRequest(
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        onCompleted: @escaping (Data) async throws -> Void
    ) async -> Result<Void, NetworkFailure> {

        guard await connectionManager.hasConnection(connectId) else {
            Log.error("[NetworkProvider] Connection \(connectId) not found")
            return .failure(NetworkFailure(
                type: .dataCenterNotResponding,
                message: "Connection unavailable - server may be recovering",
            ))
        }

        let encryptResult = await connectionManager.encryptOutbound(connectId, plainData: plainBuffer)
        guard case .success(let encryptedEnvelope) = encryptResult else {
            if case .failure(let protocolError) = encryptResult {
                Log.error("[NetworkProvider] Encryption failed: \(protocolError.message)")
                return .failure(NetworkFailure(
                    type: .encryptionFailed,
                    message: "Encryption failed: \(protocolError.message)",
                    underlyingError: protocolError
                ))
            }
            return .failure(NetworkFailure(
                type: .encryptionFailed,
                message: "Encryption failed with unknown error",
            ))
        }

        Log.info("[NetworkProvider]  Encrypted outbound for \(serviceType.rawValue)")

        let responseEnvelope = await sendViaGRPC(serviceType: serviceType, envelope: encryptedEnvelope)

        guard case .success(let inboundEnvelope) = responseEnvelope else {
            if case .failure(let networkError) = responseEnvelope {
                return .failure(networkError)
            }
            return .failure(NetworkFailure(
                type: .serverError,
                message: "gRPC request failed",
            ))
        }

        let decryptResult = await connectionManager.decryptInbound(connectId, envelope: inboundEnvelope)
        guard case .success(let decryptedData) = decryptResult else {
            if case .failure(let protocolError) = decryptResult {
                Log.error("[NetworkProvider] Decryption failed: \(protocolError.message)")
                return .failure(NetworkFailure(
                    type: .decryptionFailed,
                    message: "Decryption failed: \(protocolError.message)",
                    underlyingError: protocolError
                ))
            }
            return .failure(NetworkFailure(
                type: .decryptionFailed,
                message: "Decryption failed with unknown error",
            ))
        }

        Log.info("[NetworkProvider]  Decrypted inbound for \(serviceType.rawValue), size: \(decryptedData.count)")

        do {
            try await onCompleted(decryptedData)
            notifyServerConnected(connectId: connectId)
            return .success(())
        } catch {
            Log.error("[NetworkProvider] Completion handler failed: \(error)")
            return .failure(NetworkFailure(
                type: .serverError,
                message: "Failed to process response: \(error.localizedDescription)",
            ))
        }
    }

    private func executeUnauthenticatedRequest(
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        onCompleted: @escaping (Data) async throws -> Void
    ) async -> Result<Void, NetworkFailure> {

        Log.info("[NetworkProvider] [WARNING] Sending PLAIN (unencrypted) request for \(serviceType.rawValue)")

        let plainEnvelope = SecureEnvelope(
            metaData: Data(),
            encryptedPayload: plainBuffer,
            resultCode: Data(),
            authenticationTag: Data(),
            timestamp: Date(),
            errorDetails: nil,
            headerNonce: Data(),
            dhPublicKey: nil
        )

        let responseEnvelope = await sendViaGRPC(serviceType: serviceType, envelope: plainEnvelope)

        guard case .success(let inboundEnvelope) = responseEnvelope else {
            if case .failure(let networkError) = responseEnvelope {
                return .failure(networkError)
            }
            return .failure(NetworkFailure(
                type: .serverError,
                message: "gRPC request failed",
            ))
        }

        let responseData = inboundEnvelope.encryptedPayload

        Log.info("[NetworkProvider] [WARNING] Received PLAIN response for \(serviceType.rawValue), size: \(responseData.count)")

        do {
            try await onCompleted(responseData)
            notifyServerConnected(connectId: connectId)
            return .success(())
        } catch {
            Log.error("[NetworkProvider] Completion handler failed: \(error)")
            return .failure(NetworkFailure(
                type: .serverError,
                message: "Failed to process response: \(error.localizedDescription)",
            ))
        }
    }

    private func registerPendingRequest(
        requestKey: String,
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        onCompleted: @escaping (Data) async throws -> Void
    ) {
        pendingRequestManager.registerPendingRequest(requestId: requestKey) {

            let result = await self.executeUnaryRequest(
                connectId: connectId,
                serviceType: serviceType,
                plainBuffer: plainBuffer,
                allowDuplicates: true,
                waitForRecovery: false,
                onCompleted: onCompleted
            )

            if case .failure(let error) = result {
                throw NSError(
                    domain: "NetworkProvider",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: error.message]
                )
            }
        }
    }

    private func sendViaGRPC(serviceType: RPCServiceType, envelope: SecureEnvelope) async -> Result<SecureEnvelope, NetworkFailure> {
        Log.debug("[NetworkProvider] Routing \(serviceType.rawValue) to service client")

        switch serviceType {

        case .registrationInit, .registrationComplete, .signInInit, .signInComplete,
             .logout, .validateMobileNumber, .checkMobileAvailability, .verifyOtp:
            let membershipClient = MembershipServiceClient(channelManager: channelManager)
            return await routeToMembershipService(
                serviceType: serviceType,
                envelope: envelope,
                client: membershipClient
            )

        case .registerDevice, .updateDeviceInfo, .getDeviceStatus:
            let deviceClient = DeviceServiceClient(channelManager: channelManager)
            return await routeToDeviceService(
                serviceType: serviceType,
                envelope: envelope,
                client: deviceClient
            )

        case .restoreSecureChannel, .establishSecureChannel:
            let secureChannelClient = SecureChannelServiceClient(channelManager: channelManager)
            return await routeToSecureChannelService(
                serviceType: serviceType,
                envelope: envelope,
                client: secureChannelClient
            )

        case .sendMessage:
            let secureChannelClient = SecureChannelServiceClient(channelManager: channelManager)
            return await secureChannelClient.sendEncryptedMessage(envelope: envelope)
        }
    }

    private func routeToMembershipService(
        serviceType: RPCServiceType,
        envelope: SecureEnvelope,
        client: MembershipServiceClient
    ) async -> Result<SecureEnvelope, NetworkFailure> {
        Log.warning("[NetworkProvider] [STUB] routeToMembershipService not fully implemented for \(serviceType.rawValue)")
        return .failure(NetworkFailure(
            type: .unknown,
            message: "routeToMembershipService stub - needs type conversion SecureEnvelope <-> Common_SecureEnvelope"
        ))
    }

    private func routeToDeviceService(
        serviceType: RPCServiceType,
        envelope: SecureEnvelope,
        client: DeviceServiceClient
    ) async -> Result<SecureEnvelope, NetworkFailure> {
        Log.warning("[NetworkProvider] [STUB] routeToDeviceService not fully implemented for \(serviceType.rawValue)")
        return .failure(NetworkFailure(
            type: .unknown,
            message: "routeToDeviceService stub - needs type conversion SecureEnvelope <-> Common_SecureEnvelope"
        ))
    }

    private func routeToSecureChannelService(
        serviceType: RPCServiceType,
        envelope: SecureEnvelope,
        client: SecureChannelServiceClient
    ) async -> Result<SecureEnvelope, NetworkFailure> {
        Log.warning("[NetworkProvider] [STUB] routeToSecureChannelService not fully implemented for \(serviceType.rawValue)")
        return .failure(NetworkFailure(
            type: .unknown,
            message: "routeToSecureChannelService stub - needs type conversion SecureEnvelope <-> Common_SecureEnvelope"
        ))
    }

    public func establishSecureChannel(
        connectId: UInt32,
        remotePublicKeyBundle: PublicKeyBundle
    ) async -> Result<SessionState, NetworkFailure> {

        guard let session = await connectionManager.getConnection(connectId) else {
            return .failure(NetworkFailure(
                type: .dataCenterNotResponding,
                message: "Connection \(connectId) not found",
            ))
        }

        let sharedSecret: Data
        do {
            sharedSecret = try session.identityKeys.x3dhDeriveSharedSecret(
                remoteBundle: remotePublicKeyBundle,
                info: Data("EcliptixSecureChannel".utf8)
            )
        } catch {
            Log.error("[NetworkProvider] X3DH key agreement failed: \(error.localizedDescription)")
            return .failure(NetworkFailure(
                type: .authenticationRequired,
                message: "Key agreement failed: \(error.localizedDescription)",
            ))
        }

        let ratchetResult = ProtocolConnection.create(
            connectionId: connectId,
            isInitiator: true,
            initialRootKey: sharedSecret,
            initialChainKey: sharedSecret
        )

        guard case .success(let doubleRatchet) = ratchetResult else {
            if case .failure(let error) = ratchetResult {
                Log.error("[NetworkProvider] Double Ratchet initialization failed: \(error.message)")
                return .failure(NetworkFailure(
                    type: .serverError,
                    message: "Protocol initialization failed: \(error.message)",
                ))
            }
            return .failure(NetworkFailure(
                type: .serverError,
                message: "Protocol initialization failed",
            ))
        }

        await connectionManager.updateConnection(connectId, doubleRatchet: doubleRatchet)

        Log.info("[NetworkProvider] Secure channel established for connection \(connectId)")

        let sendingIndex: UInt32
        let receivingIndex: UInt32
        do {
            sendingIndex = try doubleRatchet.getSendingChainIndex()
            receivingIndex = try doubleRatchet.getReceivingChainIndex()
        } catch {
            return .failure(NetworkFailure(
                type: .serverError,
                message: "Failed to get chain indices: \(error.localizedDescription)"
            ))
        }

        let sessionState = SessionState(
            connectId: connectId,
            sendingChainIndex: sendingIndex,
            receivingChainIndex: receivingIndex,
            establishedAt: Date()
        )

        return .success(sessionState)
    }

    public func restoreSecureChannel(
        connectId: UInt32,
        savedState: SessionState,
        identityKeys: IdentityKeys
    ) async -> Result<Bool, NetworkFailure> {

        Log.warning("[NetworkProvider] restoreSecureChannel not yet fully implemented")

        return .failure(NetworkFailure(
            type: .serverError,
            message: "Secure channel restoration not yet implemented",
        ))
    }

    public struct SessionState {
        public let connectId: UInt32
        public let sendingChainIndex: UInt32
        public let receivingChainIndex: UInt32
        public let establishedAt: Date

        public init(connectId: UInt32, sendingChainIndex: UInt32, receivingChainIndex: UInt32, establishedAt: Date) {
            self.connectId = connectId
            self.sendingChainIndex = sendingChainIndex
            self.receivingChainIndex = receivingChainIndex
            self.establishedAt = establishedAt
        }
    }

    public func clearExhaustedOperations() async {
        await retryStrategy.clearExhaustedOperations()
        Log.info("[NetworkProvider]  Cleared exhausted operations - fresh retry enabled")
    }

    public func markConnectionHealthy(connectId: UInt32) async {
        await retryStrategy.markConnectionHealthy(connectId: connectId)
        Log.info("[NetworkProvider] [OK] Connection \(connectId) marked as healthy")
    }

    public var pendingRequestCount: Int {
        return pendingRequestManager.queueSize
    }

    public var pendingRequestStatistics: (queued: Int, processed: Int, failed: Int) {
        return pendingRequestManager.statistics
    }

    public func tripCircuitBreaker() {
        circuitBreaker.trip()
        Log.warning("[NetworkProvider] [WARNING] Circuit breaker manually tripped")
    }

    public func resetCircuitBreaker() {
        circuitBreaker.reset()
        Log.info("[NetworkProvider]  Circuit breaker manually reset")
    }

    public func resetCircuitBreakerForConnection(_ connectId: UInt32) {
        circuitBreaker.resetConnection(connectId)
        Log.info("[NetworkProvider]  Circuit breaker reset for connection \(connectId)")
    }

    public func getCircuitBreakerMetrics() -> CircuitBreakerMetrics {
        return circuitBreaker.getMetrics()
    }

    public func getConnectionCircuitMetrics(connectId: UInt32) -> ConnectionCircuitMetrics? {
        return circuitBreaker.getConnectionMetrics(connectId: connectId)
    }

    public func getConnectionHealth(connectId: UInt32) -> ConnectionHealthMonitor.ConnectionHealth? {
        return healthMonitor.getHealth(connectId: connectId)
    }

    public func getAllConnectionHealth() -> [ConnectionHealthMonitor.ConnectionHealth] {
        return healthMonitor.getAllHealth()
    }

    public func getHealthStatistics() -> HealthStatistics {
        return healthMonitor.getStatistics()
    }

    public func resetConnectionHealth(connectId: UInt32) {
        healthMonitor.resetHealth(connectId: connectId)
    }

    public var healthStatusPublisher: PassthroughSubject<ConnectionHealthMonitor.ConnectionHealth, Never> {
        return healthMonitor.healthStatusPublisher
    }

    public func shutdown() async {
        isShutdown = true

        if let defaultConnectivity = connectivityService as? DefaultConnectivityService {
            defaultConnectivity.stopMonitoring()
        }

        await channelManager.shutdown()

        await connectionManager.removeAll()

        activeRequests.removeAll()

        pendingRequestManager.clearQueue()

        Log.info("[NetworkProvider] [OK] Shutdown complete")
    }

    internal func notifyServerConnected(connectId: UInt32) {
        if let defaultConnectivity = connectivityService as? DefaultConnectivityService {
            defaultConnectivity.notifyServerConnected(connectId: connectId)
        }
    }

    internal func notifyServerDisconnected(failure: NetworkFailure, connectId: UInt32) {
        Log.warning("[NetworkProvider] [STUB] notifyServerDisconnected conversion between NetworkFailure types not implemented")
    }

    public var connectivity: ConnectivityService {
        return connectivityService
    }

    public var isOffline: Bool {
        return isInOutage || connectivityService.isOffline
    }

    public func requestManualRetry(connectId: UInt32? = nil) async {
        await connectivityService.requestManualRetry(connectId: connectId)
    }
}
