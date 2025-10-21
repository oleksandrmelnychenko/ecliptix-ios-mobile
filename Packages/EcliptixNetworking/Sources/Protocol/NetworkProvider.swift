import Foundation
import Combine
import EcliptixCore
import EcliptixSecurity

// MARK: - Network Provider
/// Central orchestrator for network operations with protocol encryption
/// Migrated from: Ecliptix.Core/Infrastructure/Network/Core/Providers/NetworkProvider.cs (2293 lines)
///
/// Responsibilities:
/// - Manages protocol connections (DoubleRatchet sessions)
/// - Encrypts/decrypts all network traffic
/// - Handles request deduplication
/// - Coordinates outage recovery
/// - Integrates with service clients
@MainActor
public final class NetworkProvider {

    // MARK: - Properties

    private let connectionManager: ProtocolConnectionManager
    private let channelManager: GRPCChannelManager
    private let retryStrategy: RetryStrategy
    private let pendingRequestManager: PendingRequestManager
    private let connectivityMonitor: NetworkConnectivityMonitor

    /// Active requests for deduplication (request key -> cancellation handle)
    private var activeRequests: [String: Task<Void, Never>] = [:]
    private let activeRequestsLock = NSLock()

    /// Outage state management
    private var isInOutage: Bool = false
    private var outageRecoveryContinuation: CheckedContinuation<Void, Never>?
    private let outageLock = NSLock()

    /// Application instance settings
    private var applicationInstanceSettings: ApplicationInstanceSettings?

    /// Cancellation token for shutdown
    private var isShutdown: Bool = false

    // MARK: - Types

    /// Application instance settings
    public struct ApplicationInstanceSettings {
        public let appInstanceId: UUID
        public let deviceId: UUID
        public let culture: String
        public let membershipId: String?

        public init(appInstanceId: UUID, deviceId: UUID, culture: String = "en-US", membershipId: String? = nil) {
            self.appInstanceId = appInstanceId
            self.deviceId = deviceId
            self.culture = culture
            self.membershipId = membershipId
        }
    }

    /// RPC Service Type (maps to C# RpcServiceType)
    public enum RPCServiceType: String {
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

    // MARK: - Initialization

    public init(
        connectionManager: ProtocolConnectionManager = ProtocolConnectionManager(),
        channelManager: GRPCChannelManager,
        retryConfiguration: RetryConfiguration = .default,
        connectivityMonitor: NetworkConnectivityMonitor = NetworkConnectivityMonitor()
    ) {
        self.connectionManager = connectionManager
        self.channelManager = channelManager
        self.retryStrategy = RetryStrategy(configuration: retryConfiguration)
        self.pendingRequestManager = PendingRequestManager()
        self.connectivityMonitor = connectivityMonitor

        // Start monitoring network connectivity
        connectivityMonitor.start()

        // Subscribe to network status changes
        Task {
            await self.subscribeToNetworkChanges()
        }
    }

    // MARK: - Network Connectivity

    /// Subscribes to network status changes for outage recovery
    private func subscribeToNetworkChanges() async {
        for await status in connectivityMonitor.statusPublisher.values {
            switch status {
            case .connected:
                // Exit outage when network restored
                if isInOutage {
                    exitOutage()
                }

            case .disconnected:
                // Enter outage when network lost
                if !isInOutage {
                    enterOutage()
                }

            case .restoring:
                // Network is attempting to restore
                Log.info("[NetworkProvider] Network is restoring...")
            }
        }
    }

    // MARK: - Outage Management

    /// Enters outage mode - queues all new requests
    /// Migrated from: EnterOutage()
    private func enterOutage() {
        outageLock.lock()
        defer { outageLock.unlock() }

        guard !isInOutage else { return }

        isInOutage = true
        Log.warning("[NetworkProvider] Entered network outage mode")
    }

    /// Exits outage mode - resumes queued requests
    /// Migrated from: ExitOutage()
    private func exitOutage() {
        outageLock.lock()
        let continuation = outageRecoveryContinuation
        outageRecoveryContinuation = nil
        isInOutage = false
        outageLock.unlock()

        Log.info("[NetworkProvider] Exited network outage mode")

        // Resume all waiting requests
        continuation?.resume()

        // Retry all pending requests that failed during outage
        Task {
            let successCount = await pendingRequestManager.retryAllPendingRequests()
            if successCount > 0 {
                Log.info("[NetworkProvider] 🔄 Outage recovery: \(successCount) pending requests succeeded")
            }
        }
    }

    /// Waits for outage to be resolved before executing request
    /// Migrated from: WaitForOutageRecoveryAsync()
    private func waitForOutageRecovery() async throws {
        outageLock.lock()
        guard isInOutage else {
            outageLock.unlock()
            return
        }
        outageLock.unlock()

        Log.info("[NetworkProvider] Waiting for outage recovery...")

        await withCheckedContinuation { continuation in
            outageLock.lock()
            if !isInOutage {
                outageLock.unlock()
                continuation.resume()
            } else {
                outageRecoveryContinuation = continuation
                outageLock.unlock()
            }
        }
    }

    // MARK: - Request Deduplication

    /// Generates a unique request key for deduplication
    /// Migrated from: NetworkProvider request key generation
    private func generateRequestKey(connectId: UInt32, serviceType: RPCServiceType, plainBuffer: Data) -> String {
        // For auth operations, use service type only
        if serviceType == .signInInit || serviceType == .signInComplete {
            return "\(connectId)_\(serviceType.rawValue)_auth_operation"
        }

        // For other operations, hash first bytes of buffer
        let bytesToHash = min(plainBuffer.count, 32)
        let prefix = plainBuffer.prefix(bytesToHash)
        let hexString = prefix.map { String(format: "%02x", $0) }.joined()

        return "\(connectId)_\(serviceType.rawValue)_\(hexString)"
    }

    /// Checks if a service type allows duplicate requests
    private func canServiceTypeBeDuplicated(_ serviceType: RPCServiceType) -> Bool {
        // Some service types can have concurrent requests
        switch serviceType {
        case .sendMessage, .updateDeviceInfo:
            return true
        default:
            return false
        }
    }

    // MARK: - Connection Management

    /// Initializes a protocol connection with identity keys
    /// Migrated from: InitiateEcliptixProtocolSystem()
    public func initiateProtocolConnection(connectId: UInt32, identityKeys: IdentityKeys) {
        connectionManager.addConnection(connectId: connectId, identityKeys: identityKeys)
        Log.info("[NetworkProvider] Initiated protocol connection \(connectId)")
    }

    /// Removes a protocol connection
    /// Migrated from: CleanupStreamProtocolAsync()
    public func cleanupProtocolConnection(_ connectId: UInt32) {
        connectionManager.removeConnection(connectId)
        Log.info("[NetworkProvider] Cleaned up protocol connection \(connectId)")
    }

    /// Sets application instance settings
    public func setApplicationInstanceSettings(_ settings: ApplicationInstanceSettings) {
        self.applicationInstanceSettings = settings
        Log.info("[NetworkProvider] Application instance settings configured")
    }

    // MARK: - Request Execution

    /// Executes a unary RPC request with protocol encryption
    /// Migrated from: ExecuteUnaryRequestAsync()
    ///
    /// - Parameters:
    ///   - connectId: Protocol connection identifier
    ///   - serviceType: Type of RPC service
    ///   - plainBuffer: Plain (unencrypted) request data
    ///   - allowDuplicates: Allow duplicate concurrent requests
    ///   - waitForRecovery: Wait for network outage recovery
    ///   - onCompleted: Callback with decrypted response data
    /// - Returns: Result with Unit or NetworkFailure
    public func executeUnaryRequest(
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        allowDuplicates: Bool = false,
        waitForRecovery: Bool = true,
        onCompleted: @escaping (Data) async throws -> Void
    ) async -> Result<Void, NetworkFailure> {

        // Generate request key for deduplication
        let requestKey = generateRequestKey(connectId: connectId, serviceType: serviceType, plainBuffer: plainBuffer)

        // Check for duplicates
        let shouldAllowDuplicates = allowDuplicates || canServiceTypeBeDuplicated(serviceType)
        if !shouldAllowDuplicates {
            activeRequestsLock.lock()
            if activeRequests[requestKey] != nil {
                activeRequestsLock.unlock()
                Log.warning("[NetworkProvider] Duplicate request rejected: \(requestKey)")
                return .failure(NetworkFailure(
                    type: .invalidRequest,
                    message: "Duplicate request rejected",
                    shouldRetry: false
                ))
            }
            activeRequestsLock.unlock()
        }

        // Execute request with deduplication tracking
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
            // Remove from active requests if cancelled
            if !shouldAllowDuplicates {
                activeRequestsLock.lock()
                activeRequests.removeValue(forKey: requestKey)
                activeRequestsLock.unlock()
            }
        }
    }

    /// Executes a unary RPC request with retry strategy
    /// This is the recommended method to use - it wraps executeUnaryRequest with retry logic
    public func executeWithRetry<T>(
        operationName: String,
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        allowDuplicates: Bool = false,
        waitForRecovery: Bool = true,
        maxRetries: Int? = nil,
        onCompleted: @escaping (Data) async throws -> T
    ) async -> Result<T, NetworkFailure> {

        // Execute with retry strategy
        let result = await retryStrategy.executeRPCOperation(
            operationName: operationName,
            connectId: connectId,
            serviceType: serviceType,
            maxRetries: maxRetries
        ) { attempt in
            Log.debug("[NetworkProvider] Executing '\(operationName)' attempt \(attempt)")

            // Execute the request
            let requestResult = await executeUnaryRequest(
                connectId: connectId,
                serviceType: serviceType,
                plainBuffer: plainBuffer,
                allowDuplicates: allowDuplicates,
                waitForRecovery: waitForRecovery
            ) { responseData in
                try await onCompleted(responseData)
            }

            // Map Result<Void, NetworkFailure> to Result<T, NetworkFailure>
            switch requestResult {
            case .success:
                // We need to return the actual value from onCompleted
                // For now, return Unit result (will be improved with better API)
                return .success(() as! T)
            case .failure(let error):
                return .failure(error)
            }
        }

        return result
    }

    /// Internal request execution with encryption/decryption
    private func executeRequestInternal(
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        requestKey: String,
        shouldAllowDuplicates: Bool,
        waitForRecovery: Bool,
        onCompleted: @escaping (Data) async throws -> Void
    ) async -> Result<Void, NetworkFailure> {

        // Track active request
        let requestTask = Task { }
        if !shouldAllowDuplicates {
            activeRequestsLock.lock()
            activeRequests[requestKey] = requestTask
            activeRequestsLock.unlock()
        }

        defer {
            // Remove from active requests
            if !shouldAllowDuplicates {
                activeRequestsLock.lock()
                activeRequests.removeValue(forKey: requestKey)
                activeRequestsLock.unlock()
            }
        }

        // Wait for outage recovery if needed
        if waitForRecovery {
            do {
                try await waitForOutageRecovery()
            } catch {
                return .failure(NetworkFailure(
                    type: .operationCancelled,
                    message: "Request cancelled during outage recovery",
                    shouldRetry: false
                ))
            }
        }

        // Check if connection exists
        guard connectionManager.hasConnection(connectId) else {
            Log.error("[NetworkProvider] Connection \(connectId) not found")
            return .failure(NetworkFailure(
                type: .dataCenterNotResponding,
                message: "Connection unavailable - server may be recovering",
                shouldRetry: true
            ))
        }

        // Encrypt plain buffer with protocol
        let encryptResult = connectionManager.encryptOutbound(connectId, plainData: plainBuffer)
        guard case .success(let encryptedEnvelope) = encryptResult else {
            if case .failure(let protocolError) = encryptResult {
                Log.error("[NetworkProvider] Encryption failed: \(protocolError.message)")
                return .failure(NetworkFailure(
                    type: .serverError,
                    message: "Encryption failed: \(protocolError.message)",
                    shouldRetry: false
                ))
            }
            return .failure(NetworkFailure(
                type: .serverError,
                message: "Encryption failed",
                shouldRetry: false
            ))
        }

        Log.info("[NetworkProvider] Encrypted outbound for \(serviceType.rawValue)")

        // Send encrypted request via gRPC
        // TODO: Replace with actual gRPC service call once protobuf is generated
        // For now, return placeholder error
        let responseEnvelope = await sendViaGRPC(serviceType: serviceType, envelope: encryptedEnvelope)

        guard case .success(let inboundEnvelope) = responseEnvelope else {
            if case .failure(let networkError) = responseEnvelope {
                return .failure(networkError)
            }
            return .failure(NetworkFailure(
                type: .serverError,
                message: "gRPC request failed",
                shouldRetry: true
            ))
        }

        // Decrypt response
        let decryptResult = connectionManager.decryptInbound(connectId, envelope: inboundEnvelope)
        guard case .success(let decryptedData) = decryptResult else {
            if case .failure(let protocolError) = decryptResult {
                Log.error("[NetworkProvider] Decryption failed: \(protocolError.message)")
                return .failure(NetworkFailure(
                    type: .serverError,
                    message: "Decryption failed: \(protocolError.message)",
                    shouldRetry: false
                ))
            }
            return .failure(NetworkFailure(
                type: .serverError,
                message: "Decryption failed",
                shouldRetry: false
            ))
        }

        Log.info("[NetworkProvider] Decrypted inbound for \(serviceType.rawValue), size: \(decryptedData.count)")

        // Call completion handler with decrypted data
        do {
            try await onCompleted(decryptedData)
            return .success(())
        } catch {
            Log.error("[NetworkProvider] Completion handler failed: \(error)")

            let failure = NetworkFailure(
                type: .serverError,
                message: "Failed to process response: \(error.localizedDescription)",
                shouldRetry: false
            )

            // Register for retry if appropriate
            if failure.shouldRetry && waitForRecovery {
                registerPendingRequest(
                    requestKey: requestKey,
                    connectId: connectId,
                    serviceType: serviceType,
                    plainBuffer: plainBuffer,
                    onCompleted: onCompleted
                )
            }

            return .failure(failure)
        }
    }

    /// Registers a failed request for later retry
    /// Migrated from: RegisterPendingRequest()
    private func registerPendingRequest(
        requestKey: String,
        connectId: UInt32,
        serviceType: RPCServiceType,
        plainBuffer: Data,
        onCompleted: @escaping (Data) async throws -> Void
    ) {
        pendingRequestManager.registerPendingRequest(requestId: requestKey) {
            // Retry action - re-execute the request
            let result = await self.executeUnaryRequest(
                connectId: connectId,
                serviceType: serviceType,
                plainBuffer: plainBuffer,
                allowDuplicates: true, // Allow during retry
                waitForRecovery: false, // Don't wait again
                onCompleted: onCompleted
            )

            // Throw error if failed to propagate to PendingRequestManager
            if case .failure(let error) = result {
                throw NSError(
                    domain: "NetworkProvider",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: error.message]
                )
            }
        }
    }

    /// Sends encrypted envelope via gRPC
    /// TODO: Replace with actual protobuf-generated service clients
    private func sendViaGRPC(serviceType: RPCServiceType, envelope: SecureEnvelope) async -> Result<SecureEnvelope, NetworkFailure> {
        // Placeholder - will be replaced with actual gRPC calls after protobuf generation
        Log.warning("[NetworkProvider] sendViaGRPC is a placeholder - awaiting protobuf generation")

        return .failure(NetworkFailure(
            type: .serverError,
            message: "Protobuf service clients not yet generated. Run ./generate-protos.sh",
            shouldRetry: false
        ))
    }

    // MARK: - Secure Channel Operations

    /// Establishes a secure channel using X3DH + Double Ratchet
    /// Migrated from: EstablishSecrecyChannelAsync()
    public func establishSecureChannel(
        connectId: UInt32,
        remotePublicKeyBundle: PublicKeyBundle
    ) async -> Result<SessionState, NetworkFailure> {

        guard let session = connectionManager.getConnection(connectId) else {
            return .failure(NetworkFailure(
                type: .dataCenterNotResponding,
                message: "Connection \(connectId) not found",
                shouldRetry: false
            ))
        }

        // Perform X3DH key agreement
        let sharedSecretResult = session.identityKeys.x3dhDeriveSharedSecret(
            remoteBundle: remotePublicKeyBundle,
            info: Data("EcliptixSecureChannel".utf8)
        )

        guard case .success(let sharedSecret) = sharedSecretResult else {
            if case .failure(let error) = sharedSecretResult {
                Log.error("[NetworkProvider] X3DH key agreement failed: \(error.message)")
                return .failure(NetworkFailure(
                    type: .authenticationRequired,
                    message: "Key agreement failed: \(error.message)",
                    shouldRetry: false
                ))
            }
            return .failure(NetworkFailure(
                type: .authenticationRequired,
                message: "Key agreement failed",
                shouldRetry: false
            ))
        }

        // Initialize Double Ratchet as initiator
        // Note: ProtocolConnection needs finalization after creation
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
                    shouldRetry: false
                ))
            }
            return .failure(NetworkFailure(
                type: .serverError,
                message: "Protocol initialization failed",
                shouldRetry: false
            ))
        }

        // Update connection with Double Ratchet
        connectionManager.updateConnection(connectId, doubleRatchet: doubleRatchet)

        Log.info("[NetworkProvider] Secure channel established for connection \(connectId)")

        // Return session state
        let sessionState = SessionState(
            connectId: connectId,
            sendingChainIndex: doubleRatchet.sendingChainIndex,
            receivingChainIndex: doubleRatchet.receivingChainIndex,
            establishedAt: Date()
        )

        return .success(sessionState)
    }

    /// Restores a secure channel from saved state
    /// Migrated from: RestoreSecrecyChannelAsync()
    public func restoreSecureChannel(
        connectId: UInt32,
        savedState: SessionState,
        identityKeys: IdentityKeys
    ) async -> Result<Bool, NetworkFailure> {

        // TODO: Implement restoration from saved DoubleRatchet state
        // This requires deserializing the ratchet state from storage

        Log.warning("[NetworkProvider] restoreSecureChannel not yet fully implemented")

        return .failure(NetworkFailure(
            type: .serverError,
            message: "Secure channel restoration not yet implemented",
            shouldRetry: false
        ))
    }

    // MARK: - Session State

    /// Session state for a secure channel
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

    // MARK: - Manual Retry

    /// Clears all exhausted operations and allows fresh retry attempts
    /// Useful for "Retry" button in UI when all operations are exhausted
    /// Migrated from: ClearExhaustedOperations()
    public func clearExhaustedOperations() {
        retryStrategy.clearExhaustedOperations()
        Log.info("[NetworkProvider] 🔄 Cleared exhausted operations - fresh retry enabled")
    }

    /// Marks a connection as healthy, resetting exhaustion state
    /// Migrated from: MarkConnectionHealthy()
    public func markConnectionHealthy(connectId: UInt32) {
        retryStrategy.markConnectionHealthy(connectId: connectId)
        Log.info("[NetworkProvider] ✅ Connection \(connectId) marked as healthy")
    }

    /// Current count of pending requests waiting for retry
    public var pendingRequestCount: Int {
        return pendingRequestManager.pendingRequestCount
    }

    /// Publisher for observing pending request count changes
    public var pendingCountPublisher: PassthroughSubject<Int, Never> {
        return pendingRequestManager.pendingCountPublisher
    }

    // MARK: - Shutdown

    /// Shuts down the network provider
    public func shutdown() async {
        isShutdown = true

        // Stop connectivity monitoring
        connectivityMonitor.stop()

        // Close gRPC channel
        await channelManager.shutdown()

        // Clear all connections
        connectionManager.removeAll()

        // Clear active requests
        activeRequestsLock.lock()
        activeRequests.removeAll()
        activeRequestsLock.unlock()

        // Cancel all pending requests
        pendingRequestManager.cancelAllPendingRequests()

        Log.info("[NetworkProvider] Shutdown complete")
    }
}
