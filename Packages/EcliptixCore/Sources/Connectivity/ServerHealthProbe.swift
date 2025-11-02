import Combine
import Foundation

public final class ServerHealthProbe: @unchecked Sendable {

    private let connectivityPublisher: ConnectivityPublisher
    private var healthCheckTimer: Timer?
    private let healthCheckInterval: TimeInterval
    private var isMonitoring = false
    private var currentServerStatus: ConnectivityStatus = .disconnected

    private weak var networkProvider: AnyObject?

    public init(
        connectivityPublisher: ConnectivityPublisher,
        healthCheckInterval: TimeInterval = 30.0
    ) {
        self.connectivityPublisher = connectivityPublisher
        self.healthCheckInterval = healthCheckInterval

        Log.info("[ServerHealthProbe] Service initialized (interval: \(healthCheckInterval)s)")
    }

    deinit {
        stopMonitoring()
    }

    public func startMonitoring() {
        guard !isMonitoring else {
            Log.debug("[ServerHealthProbe] Already monitoring")
            return
        }

        healthCheckTimer = Timer.scheduledTimer(
            withTimeInterval: healthCheckInterval,
            repeats: true
        ) { [weak self] _ in
            self?.performHealthCheck()
        }

        performHealthCheck()

        isMonitoring = true
        Log.info("[ServerHealthProbe] Started monitoring server health")
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }

        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        isMonitoring = false

        Log.info("[ServerHealthProbe] Stopped monitoring")
    }

    public func triggerHealthCheck() {
        guard isMonitoring else {
            Log.debug("[ServerHealthProbe] Not monitoring, skipping manual health check")
            return
        }

        performHealthCheck()
    }

    public func notifyServerConnected(connectId: UInt32? = nil) {
        currentServerStatus = .connected

        Task { [connectivityPublisher] in
            await connectivityPublisher.publish(
                .connected(connectId: connectId, reason: .handshakeSucceeded)
            )
        }

        Log.info("[ServerHealthProbe] [OK] Server connection established")
    }

    public func notifyServerConnecting(connectId: UInt32? = nil) {
        currentServerStatus = .connecting

        Task { [connectivityPublisher] in
            await connectivityPublisher.publish(
                .connecting(connectId: connectId, reason: .handshakeStarted)
            )
        }

        Log.debug("[ServerHealthProbe]  Server connection attempt started")
    }

    public func notifyServerDisconnected(
        failure: NetworkFailure,
        connectId: UInt32? = nil
    ) {
        currentServerStatus = .disconnected

        Task { [connectivityPublisher] in
            await connectivityPublisher.publish(
                .disconnected(failure: failure, connectId: connectId)
            )
        }

        Log.warning("[ServerHealthProbe] [FAILED] Server disconnected: \(failure.localizedDescription)")
    }

    public func notifyServerShuttingDown(failure: NetworkFailure) {
        currentServerStatus = .shuttingDown

        Task { [connectivityPublisher] in
            await connectivityPublisher.publish(.serverShutdown(failure: failure))
        }

        Log.warning("[ServerHealthProbe]  Server shutting down")
    }

    public func notifyRetriesExhausted(
        failure: NetworkFailure,
        connectId: UInt32? = nil,
        retries: Int
    ) {
        currentServerStatus = .retriesExhausted

        Task { [connectivityPublisher] in
            await connectivityPublisher.publish(
                .retriesExhausted(failure: failure, connectId: connectId, retries: retries)
            )
        }

        Log.error("[ServerHealthProbe]  Retries exhausted after \(retries) attempts")
    }

    public func notifyRecovering(
        failure: NetworkFailure,
        connectId: UInt32? = nil,
        retryAttempt: Int,
        backoff: TimeInterval
    ) {
        currentServerStatus = .recovering

        Task { [connectivityPublisher] in
            await connectivityPublisher.publish(
                .recovering(
                    failure: failure,
                    connectId: connectId,
                    retryAttempt: retryAttempt,
                    backoff: backoff
                )
            )
        }

        Log.debug("[ServerHealthProbe]  Recovering (retry \(retryAttempt), backoff: \(String(format: "%.1fs", backoff)))")
    }

    private func performHealthCheck() {

        Log.debug("[ServerHealthProbe]  Periodic health check (status: \(currentServerStatus))")

    }
}

extension ServerHealthProbe {

    public var serverStatus: ConnectivityStatus {
        currentServerStatus
    }

    public var isServerConnected: Bool {
        currentServerStatus == .connected
    }

    public var isServerHealthy: Bool {
        currentServerStatus == .connected || currentServerStatus == .connecting
    }
}
