@preconcurrency import Combine
import Foundation

public struct ManualRetryRequestedEvent: Sendable {
    public let connectId: UInt32?
    public let timestamp: Date

    public init(connectId: UInt32? = nil) {
        self.connectId = connectId
        self.timestamp = Date()
    }
}

public protocol ConnectivityService: AnyObject, Sendable {

    var currentSnapshot: ConnectivitySnapshot { get }

    var connectivityStream: AnyPublisher<ConnectivitySnapshot, Never> { get }

    var isOffline: Bool { get }

    func publish(_ intent: ConnectivityIntent) async

    func requestManualRetry(connectId: UInt32?) async

    func onManualRetryRequested(
        _ handler: @escaping @Sendable (ManualRetryRequestedEvent) async -> Void
    ) -> AnyCancellable

    func notifyServerDisconnected(
        failure: NetworkFailure,
        connectId: UInt32?
    )

    func notifyServerShuttingDown(failure: NetworkFailure)

    func notifyRetriesExhausted(
        failure: NetworkFailure,
        connectId: UInt32?,
        retries: Int
    )

    func notifyRecovering(
        failure: NetworkFailure,
        connectId: UInt32?,
        retryAttempt: Int,
        backoff: TimeInterval
    )

    func notifyServerReconnected(connectId: UInt32?)
}

public final class DefaultConnectivityService: @unchecked Sendable, ConnectivityService {

    private let publisher: ConnectivityPublisher
    private let internetProbe: InternetProbeService
    private let serverHealthProbe: ServerHealthProbe
    private let manualRetrySubject = PassthroughSubject<ManualRetryRequestedEvent, Never>()

    public var currentSnapshot: ConnectivitySnapshot {
        publisher.snapshot
    }

    public var connectivityStream: AnyPublisher<ConnectivitySnapshot, Never> {
        publisher.connectivityStream
    }

    public init() {
        self.publisher = ConnectivityPublisher()
        self.internetProbe = InternetProbeService(connectivityPublisher: publisher)
        self.serverHealthProbe = ServerHealthProbe(connectivityPublisher: publisher)

        Log.info("[ConnectivityService] Service initialized")
    }

    public func startMonitoring() {
        internetProbe.startMonitoring()
        serverHealthProbe.startMonitoring()

        Log.info("[ConnectivityService] [OK] Started monitoring (Internet + Server)")
    }

    public func stopMonitoring() {
        internetProbe.stopMonitoring()
        serverHealthProbe.stopMonitoring()

        Log.info("[ConnectivityService] Stopped monitoring")
    }

    public func publish(_ intent: ConnectivityIntent) async {
        await publisher.publish(intent)
    }

    public func requestManualRetry(connectId: UInt32? = nil) async {
        Log.info("[ConnectivityService]  Manual retry requested")

        let event = ManualRetryRequestedEvent(connectId: connectId)
        manualRetrySubject.send(event)

        await publisher.publish(.manualRetry(connectId: connectId))
    }

    public func onManualRetryRequested(
        _ handler: @escaping @Sendable (ManualRetryRequestedEvent) async -> Void
    ) -> AnyCancellable {
        manualRetrySubject
            .sink { event in
                Task { [handler] in
                    await handler(event)
                }
            }
    }

    public func notifyServerConnected(connectId: UInt32? = nil) {
        serverHealthProbe.notifyServerConnected(connectId: connectId)
    }

    public func notifyServerConnecting(connectId: UInt32? = nil) {
        serverHealthProbe.notifyServerConnecting(connectId: connectId)
    }

    public func notifyServerDisconnected(
        failure: NetworkFailure,
        connectId: UInt32? = nil
    ) {
        serverHealthProbe.notifyServerDisconnected(
            failure: failure,
            connectId: connectId
        )
    }

    public func notifyServerShuttingDown(failure: NetworkFailure) {
        serverHealthProbe.notifyServerShuttingDown(failure: failure)
    }

    public func notifyRetriesExhausted(
        failure: NetworkFailure,
        connectId: UInt32? = nil,
        retries: Int
    ) {
        serverHealthProbe.notifyRetriesExhausted(
            failure: failure,
            connectId: connectId,
            retries: retries
        )
    }

    public func notifyRecovering(
        failure: NetworkFailure,
        connectId: UInt32? = nil,
        retryAttempt: Int,
        backoff: TimeInterval
    ) {
        serverHealthProbe.notifyRecovering(
            failure: failure,
            connectId: connectId,
            retryAttempt: retryAttempt,
            backoff: backoff
        )
    }

    public func notifyServerReconnected(connectId: UInt32? = nil) {
        serverHealthProbe.notifyServerConnected(connectId: connectId)
    }
}

extension DefaultConnectivityService {

    public var isInternetAvailable: Bool {
        internetProbe.isInternetAvailable
    }

    public var isServerConnected: Bool {
        serverHealthProbe.isServerConnected
    }

    public var isExpensive: Bool {
        internetProbe.isExpensive
    }

    public var isConstrained: Bool {
        internetProbe.isConstrained
    }

    public var isOffline: Bool {
        let snapshot = currentSnapshot
        return snapshot.status == .disconnected ||
               snapshot.status == .shuttingDown ||
               snapshot.status == .recovering ||
               snapshot.status == .retriesExhausted ||
               snapshot.status == .unavailable
    }
}

extension ConnectivityService {

    public var offlinePublisher: AnyPublisher<Bool, Never> {
        connectivityStream
            .map { snapshot in
                snapshot.status == .disconnected ||
                snapshot.status == .shuttingDown ||
                snapshot.status == .recovering ||
                snapshot.status == .retriesExhausted ||
                snapshot.status == .unavailable
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public var connectivityRestoredPublisher: AnyPublisher<Void, Never> {
        connectivityStream
            .filter { $0.status == .connected }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    public var retriesExhaustedPublisher: AnyPublisher<ConnectivitySnapshot, Never> {
        connectivityStream
            .filter { $0.status == .retriesExhausted }
            .eraseToAnyPublisher()
    }
}
