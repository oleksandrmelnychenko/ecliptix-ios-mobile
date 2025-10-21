import Foundation
import Network
import Combine
import EcliptixCore

// MARK: - Network Status
/// Network connectivity status
public enum NetworkStatus: Equatable {
    case connected
    case disconnected
    case connectionRestored
    case retriesExhausted
}

// MARK: - Network Connectivity Monitor
/// Monitors network connectivity using NWPathMonitor
/// Migrated from: Ecliptix.Core/Infrastructure/Network/Core/Connectivity/InternetConnectivityObserver.cs
public final class NetworkConnectivityMonitor {

    // MARK: - Properties
    private let pathMonitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    private let statusSubject = CurrentValueSubject<NetworkStatus, Never>(.disconnected)

    public var statusPublisher: AnyPublisher<NetworkStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    public var isConnected: Bool {
        statusSubject.value == .connected || statusSubject.value == .connectionRestored
    }

    // MARK: - Initialization
    public init() {
        self.pathMonitor = NWPathMonitor()
        self.monitorQueue = DispatchQueue(label: "com.ecliptix.networkmonitor", qos: .utility)
    }

    // MARK: - Start Monitoring
    /// Starts monitoring network connectivity
    public func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let newStatus: NetworkStatus
            switch path.status {
            case .satisfied:
                // Check if we're restoring from disconnected state
                if self.statusSubject.value == .disconnected ||
                   self.statusSubject.value == .retriesExhausted {
                    newStatus = .connectionRestored
                } else {
                    newStatus = .connected
                }

            case .unsatisfied, .requiresConnection:
                newStatus = .disconnected

            @unknown default:
                newStatus = .disconnected
            }

            if newStatus != self.statusSubject.value {
                Log.info("Network status changed: \(self.statusSubject.value) -> \(newStatus)")
                self.statusSubject.send(newStatus)
            }
        }

        pathMonitor.start(queue: monitorQueue)
        Log.info("Network connectivity monitoring started")
    }

    // MARK: - Stop Monitoring
    /// Stops monitoring network connectivity
    public func stop() {
        pathMonitor.cancel()
        Log.info("Network connectivity monitoring stopped")
    }

    // MARK: - Set Status
    /// Manually sets the network status (for retry exhaustion, etc.)
    public func setStatus(_ status: NetworkStatus) {
        guard status != statusSubject.value else { return }
        Log.info("Network status manually set to: \(status)")
        statusSubject.send(status)
    }
}

// MARK: - Debug Description
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
