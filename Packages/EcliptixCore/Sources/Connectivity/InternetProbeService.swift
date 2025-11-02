import Combine
import Foundation
import Network

public final class InternetProbeService: @unchecked Sendable {

    private let pathMonitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    private let connectivityPublisher: ConnectivityPublisher
    private var isMonitoring = false
    private var currentPath: NWPath?

    public init(connectivityPublisher: ConnectivityPublisher) {
        self.connectivityPublisher = connectivityPublisher
        self.pathMonitor = NWPathMonitor()
        self.monitorQueue = DispatchQueue(
            label: "com.ecliptix.internet-probe",
            qos: .userInitiated
        )

        Log.info("[InternetProbe] Service initialized")
    }

    deinit {
        stopMonitoring()
    }

    public func startMonitoring() {
        guard !isMonitoring else {
            Log.debug("[InternetProbe] Already monitoring")
            return
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }

        pathMonitor.start(queue: monitorQueue)
        isMonitoring = true

        Log.info("[InternetProbe] Started monitoring internet connectivity")
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }

        pathMonitor.cancel()
        isMonitoring = false
        currentPath = nil

        Log.info("[InternetProbe] Stopped monitoring")
    }

    private func handlePathUpdate(_ path: NWPath) {
        let previousPath = currentPath
        currentPath = path

        let isConnected = path.status == .satisfied
        let wasConnected = previousPath?.status == .satisfied

        logPathDetails(path, wasConnected: wasConnected)

        guard isConnected != wasConnected else {
            Log.debug("[InternetProbe] No status change, skipping publish")
            return
        }

        if isConnected {

            Task {
                await connectivityPublisher.publish(.internetRecovered())
            }
        } else {

            Task {
                await connectivityPublisher.publish(.internetLost())
            }
        }
    }

    private func logPathDetails(_ path: NWPath, wasConnected: Bool) {
        let statusEmoji = path.status == .satisfied ? "[OK]" : "[FAILED]"
        let statusText = pathStatusText(path.status)
        let interfaces = availableInterfaces(path)

        Log.debug("[InternetProbe] \(statusEmoji) Path: \(statusText)")

        if !interfaces.isEmpty {
            Log.debug("[InternetProbe]     Interfaces: \(interfaces.joined(separator: ", "))")
        }

        if path.isExpensive {
            Log.debug("[InternetProbe]     [WARNING] Connection is expensive (cellular data)")
        }

        if path.isConstrained {
            Log.debug("[InternetProbe]     [WARNING] Connection is constrained (low data mode)")
        }

        if path.status == .satisfied && !wasConnected {
            Log.info("[InternetProbe]  Internet connection RESTORED")
        } else if path.status != .satisfied && wasConnected {
            Log.warning("[InternetProbe]  Internet connection LOST")
        }
    }

    private func pathStatusText(_ status: NWPath.Status) -> String {
        switch status {
        case .satisfied:
            return "Satisfied (Connected)"
        case .unsatisfied:
            return "Unsatisfied (No route)"
        case .requiresConnection:
            return "Requires Connection (On-demand)"
        @unknown default:
            return "Unknown"
        }
    }

    private func availableInterfaces(_ path: NWPath) -> [String] {
        path.availableInterfaces.compactMap { interface -> String? in
            switch interface.type {
            case .wifi:
                return "WiFi"
            case .cellular:
                return "Cellular"
            case .wiredEthernet:
                return "Ethernet"
            case .loopback:
                return nil
            case .other:
                return "Other"
            @unknown default:
                return "Unknown"
            }
        }
    }
}

extension InternetProbeService {

    public var isInternetAvailable: Bool {
        currentPath?.status == .satisfied
    }

    public var isExpensive: Bool {
        currentPath?.isExpensive ?? false
    }

    public var isConstrained: Bool {
        currentPath?.isConstrained ?? false
    }

    public var interfaceTypes: [NWInterface.InterfaceType] {
        currentPath?.availableInterfaces.map(\.type) ?? []
    }
}
