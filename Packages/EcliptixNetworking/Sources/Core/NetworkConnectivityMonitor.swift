import EcliptixCore
import Foundation
import Network

public enum NetworkStatus: Equatable, Sendable {
    case connected
    case disconnected
    case connectionRestored
    case retriesExhausted
}

public actor NetworkConnectivityMonitor {
    private let pathMonitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    private var currentStatus: NetworkStatus = .disconnected
    private var statusContinuation: AsyncStream<NetworkStatus>.Continuation?
    public init() {
        self.pathMonitor = NWPathMonitor()
        self.monitorQueue = DispatchQueue(label: "com.ecliptix.networkmonitor", qos: .utility)
    }

    public var statusStream: AsyncStream<NetworkStatus> {
        AsyncStream { continuation in
            self.statusContinuation = continuation

            continuation.yield(self.currentStatus)

            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.stop()
                }
            }
        }
    }

    public var status: NetworkStatus {
        currentStatus
    }

    public var isConnected: Bool {
        currentStatus == .connected || currentStatus == .connectionRestored
    }

    public func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                guard let self = self else { return }

                let previousStatus = await self.currentStatus
                let newStatus: NetworkStatus

                switch path.status {
                case .satisfied:
                    if previousStatus == .disconnected || previousStatus == .retriesExhausted {
                        newStatus = .connectionRestored
                    } else {
                        newStatus = .connected
                    }

                case .unsatisfied, .requiresConnection:
                    newStatus = .disconnected

                @unknown default:
                    newStatus = .disconnected
                }

                if newStatus != previousStatus {
                    Log.info("Network status changed: \(previousStatus) -> \(newStatus)")
                    await self.updateStatus(newStatus)
                }
            }
        }

        pathMonitor.start(queue: monitorQueue)
        Task {
            Log.info("Network connectivity monitoring started")
        }
    }

    public func stop() {
        pathMonitor.cancel()
        statusContinuation?.finish()
        statusContinuation = nil
        Task {
            Log.info("Network connectivity monitoring stopped")
        }
    }

    public func setStatus(_ status: NetworkStatus) async {
        guard status != currentStatus else { return }
        Log.info("Network status manually set to: \(status)")
        updateStatus(status)
    }
    private func updateStatus(_ newStatus: NetworkStatus) {
        currentStatus = newStatus
        statusContinuation?.yield(newStatus)
    }
}
extension NetworkStatus: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .connectionRestored: return "ConnectionRestored"
        case .retriesExhausted: return "RetriesExhausted"
        }
    }
}
