import Combine
import Foundation

@MainActor
open class ConnectivityAware: @preconcurrency ViewLifecycle {
    private let connectivityService: ConnectivityService
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var isOffline: Bool = false

    public init(connectivityService: ConnectivityService) {
        self.connectivityService = connectivityService
        setupConnectivityMonitoring()
    }


    public var offlinePublisher: AnyPublisher<Bool, Never> {
        $isOffline.eraseToAnyPublisher()
    }

    public var connectivity: ConnectivityService {
        connectivityService
    }

    open func didAppear() {}
    open func willDisappear() {}
    open func connectivityRestored() {}
    open func connectivityLost() {}

    private func setupConnectivityMonitoring() {
        connectivityService.connectivityStream
            .map { snapshot in
                snapshot.status == .disconnected ||
                snapshot.status == .unavailable ||
                snapshot.status == .shuttingDown ||
                snapshot.status == .retriesExhausted ||
                snapshot.status == .recovering
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] offline in
                guard let self = self else { return }

                let wasOffline = self.isOffline
                self.isOffline = offline

                if offline && !wasOffline {
                    self.connectivityLost()
                } else if !offline && wasOffline {
                    self.connectivityRestored()
                }
            }
            .store(in: &cancellables)
    }
}

public extension ViewLifecycle {
    var isOnline: Bool {
        !isOffline
    }

    @discardableResult
    func performIfOnline(_ action: () -> Void) -> Bool {
        guard isOnline else {
            Log.warning("[ViewLifecycle] Action blocked - offline")
            return false
        }
        action()
        return true
    }

    @discardableResult
    func performIfOnline(_ action: @escaping () async -> Void) async -> Bool {
        guard isOnline else {
            Log.warning("[ViewLifecycle] Action blocked - offline")
            return false
        }
        await action()
        return true
    }
}
