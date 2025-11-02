import EcliptixCore
import EcliptixSecurity
import Foundation

extension NetworkProvider: ConnectionRecoveryDelegate {

    private static var protocolStateStorage: SecureProtocolStateStorage?

    public func setProtocolStateStorage(_ storage: SecureProtocolStateStorage) {
        Self.protocolStateStorage = storage
    }

    private var isRecovering: Bool {
        get { isInOutage }
        set { isInOutage = newValue }
    }

    public func shouldRecoverConnection(for failure: NetworkFailure) async -> Bool {

        guard !isRecovering else {
            Log.debug("[NetworkProvider] Already in recovery, skipping duplicate recovery")
            return false
        }

        if failure.type == .protocolStateMismatch || failure.type == .handshakeFailed {
            Log.info("[NetworkProvider] Protocol state error detected, recovery required")
            return true
        }

        if failure.type == .unauthenticated || failure.type == .sessionExpired {
            let hasConnections = await connectionManager.getActiveConnectionCount() > 0
            if hasConnections {
                Log.info("[NetworkProvider] Authentication error with active connections, attempting recovery")
                return true
            }
        }

        return false
    }

    public func beginConnectionRecovery() async {
        guard !isRecovering else {
            Log.warning("[NetworkProvider] Recovery already in progress")
            return
        }

        Log.info("[NetworkProvider] [DEBUG] Beginning connection recovery")
        isRecovering = true

    }

    public func isConnectionHealthy(connectId: UInt32) async -> Bool {
        guard let session = await connectionManager.getConnection(connectId) else {
            Log.debug("[NetworkProvider] Connection \(connectId) not found")
            return false
        }

        guard session.doubleRatchet != nil else {
            Log.debug("[NetworkProvider] Connection \(connectId) has no Double Ratchet")
            return false
        }

        let isHealthy = healthMonitor.isConnectionHealthy(connectId: connectId)

        if isHealthy {
            Log.debug("[NetworkProvider] [OK] Connection \(connectId) is healthy")
        } else {
            Log.debug("[NetworkProvider] [WARNING] Connection \(connectId) is unhealthy")
        }

        return isHealthy
    }

    public func tryRestoreConnection(connectId: UInt32) async -> Bool {
        Log.info("[NetworkProvider]  Attempting to restore connection \(connectId)")

        do {
            guard let sessionData = await loadSessionState(connectId: connectId) else {
                Log.warning("[NetworkProvider] No saved session state for connection \(connectId)")

                return await tryEstablishNewConnection(connectId: connectId)
            }

            let deviceServiceClient = DeviceServiceClient(channelManager: channelManager)

            guard let membershipId = applicationInstanceSettings?.membership?.uniqueIdentifier else {
                Log.error("[NetworkProvider] No membership ID available for restoration")
                return false
            }

            try await connectionManager.restoreConnection(
                connectId: connectId,
                stateData: sessionData,
                membershipId: membershipId,
                deviceServiceClient: deviceServiceClient
            )

            Log.info("[NetworkProvider] [OK] Successfully restored connection \(connectId)")

            healthMonitor.markConnectionHealthy(connectId: connectId)

            circuitBreaker.reset()

            isRecovering = false

            return true

        } catch {
            Log.error("[NetworkProvider] [FAILED] Failed to restore connection \(connectId): \(error.localizedDescription)")

            let established = await tryEstablishNewConnection(connectId: connectId)

            if !established {
                isRecovering = false
            }

            return established
        }
    }

    private func tryEstablishNewConnection(connectId: UInt32) async -> Bool {
        Log.info("[NetworkProvider]  Attempting to establish new connection \(connectId)")

        guard applicationInstanceSettings != nil else {
            Log.error("[NetworkProvider] No application instance settings available")
            isRecovering = false
            return false
        }

        do {
            let deviceServiceClient = DeviceServiceClient(channelManager: channelManager)

            let sessionState = try await connectionManager.establishSecureChannel(
                connectId: connectId,
                deviceServiceClient: deviceServiceClient,
                exchangeType: .dataCenterEphemeralConnect
            )

            await saveSessionState(connectId: connectId, sessionData: sessionState)

            Log.info("[NetworkProvider] [OK] Successfully established new connection \(connectId)")

            healthMonitor.markConnectionHealthy(connectId: connectId)

            circuitBreaker.reset()

            isRecovering = false

            return true

        } catch {
            Log.error("[NetworkProvider] [FAILED] Failed to establish new connection \(connectId): \(error.localizedDescription)")
            isRecovering = false
            return false
        }
    }

    private func loadSessionState(connectId: UInt32) async -> Data? {
        guard let storage = Self.protocolStateStorage,
              let membershipId = applicationInstanceSettings?.membership?.uniqueIdentifier else {
            Log.debug("[NetworkProvider] No storage or membership ID available for session load")
            return nil
        }

        do {
            let sessionData = try await storage.loadState(
                connectId: "\(connectId)",
                membershipId: membershipId
            )

            if let data = sessionData {
                Log.info("[NetworkProvider] [OK] Loaded session state for connection \(connectId) - \(data.count) bytes")
            } else {
                Log.debug("[NetworkProvider] No saved session state found for connection \(connectId)")
            }

            return sessionData

        } catch {
            Log.warning("[NetworkProvider] Failed to load session state for connection \(connectId): \(error.localizedDescription)")
            return nil
        }
    }

    private func saveSessionState(connectId: UInt32, sessionData: Data) async {
        guard let storage = Self.protocolStateStorage,
              let membershipId = applicationInstanceSettings?.membership?.uniqueIdentifier else {
            Log.debug("[NetworkProvider] No storage or membership ID available for session save")
            return
        }

        do {
            try await storage.saveState(
                sessionData,
                connectId: "\(connectId)",
                membershipId: membershipId
            )

            Log.info("[NetworkProvider] [OK] Saved session state for connection \(connectId) - \(sessionData.count) bytes")

        } catch {
            Log.error("[NetworkProvider] Failed to save session state for connection \(connectId): \(error.localizedDescription)")
        }
    }
}

extension ProtocolConnectionManager {

    func getActiveConnectionCount() -> Int {

        return connections.values.filter { $0.doubleRatchet != nil }.count
    }
}
