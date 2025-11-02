import Combine
import Foundation
import SwiftUI

@MainActor
public final class ConnectivityNotification: ConnectivityAware, ObservableObject {
    @Published public private(set) var isVisible: Bool = false
    @Published public private(set) var title: String = ""
    @Published public private(set) var message: String = ""
    @Published public private(set) var showRetryButton: Bool = false
    @Published public private(set) var retryCountdown: Int = 0
    @Published public private(set) var type: NotificationType = .info

    private let localization: LocalizationService
    private var countdownTimer: Timer?
    private var autoRetryTimer: Timer?
    private var currentSnapshot: ConnectivitySnapshot?

    public let retryCommand: DefaultAsyncCommand<Void, Void>
    public let dismissCommand: DefaultAsyncCommand<Void, Void>

    public enum NotificationType {
        case info
        case warning
        case error
        case success
        case recovering

        public var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .yellow
            case .error: return .red
            case .success: return .green
            case .recovering: return .orange
            }
        }
    }

    public init(
        connectivityService: ConnectivityService,
        localization: LocalizationService
    ) {
        self.localization = localization

        self.retryCommand = DefaultAsyncCommand<Void, Void>.createAction(canExecute: false) { [connectivityService] in
            await connectivityService.requestManualRetry(connectId: nil)
        }

        self.dismissCommand = DefaultAsyncCommand<Void, Void>.createAction {

        }

        super.init(connectivityService: connectivityService)

        setupMonitoring()
    }

    deinit {
        stopTimers()
    }

    private func setupMonitoring() {
        connectivity.connectivityStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.handle(snapshot)
            }
            .store(in: &cancellables)

        localization.languageChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshLocalization()
            }
            .store(in: &cancellables)
    }

    private func handle(_ snapshot: ConnectivitySnapshot) {
        currentSnapshot = snapshot

        switch snapshot.status {
        case .connected:
            handleConnected(snapshot)

        case .connecting:
            handleConnecting(snapshot)

        case .disconnected:
            handleDisconnected(snapshot)

        case .recovering:
            handleRecovering(snapshot)

        case .unavailable:
            handleUnavailable(snapshot)

        case .shuttingDown:
            handleShuttingDown(snapshot)

        case .retriesExhausted:
            handleRetriesExhausted(snapshot)
        }
    }

    private func handleConnected(_ snapshot: ConnectivitySnapshot) {
        type = .success
        title = localization[LocalizationKeys.NetworkNotification.Connected.title]
        message = localization[LocalizationKeys.NetworkNotification.Connected.description]
        showRetryButton = false
        retryCommand.updateCanExecute(false)
        isVisible = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.isVisible = false
        }

        stopTimers()
    }

    private func handleConnecting(_ snapshot: ConnectivitySnapshot) {
        type = .info
        title = localization[LocalizationKeys.NetworkNotification.Connecting.title]
        message = connectingMessage(for: snapshot)
        showRetryButton = false
        retryCommand.updateCanExecute(false)
        isVisible = true

        stopTimers()
    }

    private func handleDisconnected(_ snapshot: ConnectivitySnapshot) {
        type = .error
        title = localization[LocalizationKeys.NetworkNotification.Disconnected.title]
        message = disconnectedMessage(for: snapshot)
        showRetryButton = false
        retryCommand.updateCanExecute(false)
        isVisible = true

        stopTimers()
    }

    private func handleRecovering(_ snapshot: ConnectivitySnapshot) {
        type = .recovering
        title = localization[LocalizationKeys.NetworkNotification.Recovering.title]
        message = recoveringMessage(for: snapshot)
        showRetryButton = false
        retryCommand.updateCanExecute(false)
        isVisible = true

        if let backoff = snapshot.retryBackoff {
            startCountdown(duration: backoff)
        }

        stopAutoRetry()
    }

    private func handleUnavailable(_ snapshot: ConnectivitySnapshot) {
        type = .warning
        title = localization[LocalizationKeys.NetworkNotification.NoInternet.title]
        message = localization[LocalizationKeys.NetworkNotification.NoInternet.description]
        showRetryButton = false
        retryCommand.updateCanExecute(false)
        isVisible = true

        stopTimers()
    }

    private func handleShuttingDown(_ snapshot: ConnectivitySnapshot) {
        type = .error
        title = localization[LocalizationKeys.NetworkNotification.ServerShutdown.title]
        message = localization[LocalizationKeys.NetworkNotification.ServerShutdown.description]
        showRetryButton = false
        retryCommand.updateCanExecute(false)
        isVisible = true

        stopTimers()
    }

    private func handleRetriesExhausted(_ snapshot: ConnectivitySnapshot) {
        type = .error
        title = localization[LocalizationKeys.NetworkNotification.RetriesExhausted.title]
        message = retriesExhaustedMessage(for: snapshot)
        showRetryButton = true
        retryCommand.updateCanExecute(true)
        isVisible = true

        stopTimers()
    }

    private func connectingMessage(for snapshot: ConnectivitySnapshot) -> String {
        switch snapshot.reason {
        case .handshakeStarted:
            return localization[LocalizationKeys.NetworkNotification.Connecting.handshake]
        case .internetRecovered:
            return localization[LocalizationKeys.NetworkNotification.Connecting.internetRestored]
        case .manualRetry:
            return localization[LocalizationKeys.NetworkNotification.Connecting.manualRetry]
        default:
            return localization[LocalizationKeys.NetworkNotification.Connecting.description]
        }
    }

    private func disconnectedMessage(for snapshot: ConnectivitySnapshot) -> String {
        if let failure = snapshot.failure {
            return failure.localizedDescription
        }

        switch snapshot.reason {
        case .rpcFailure:
            return localization[LocalizationKeys.NetworkNotification.Disconnected.rpcFailure]
        case .handshakeFailed:
            return localization[LocalizationKeys.NetworkNotification.Disconnected.handshakeFailed]
        default:
            return localization[LocalizationKeys.NetworkNotification.Disconnected.description]
        }
    }

    private func recoveringMessage(for snapshot: ConnectivitySnapshot) -> String {
        if let attempt = snapshot.retryAttempt, let backoff = snapshot.retryBackoff {
            return localization.getString(
                LocalizationKeys.NetworkNotification.Recovering.withCountdown,
                attempt,
                Int(backoff)
            )
        } else if let attempt = snapshot.retryAttempt {
            return localization.getString(
                LocalizationKeys.NetworkNotification.Recovering.attempt,
                attempt
            )
        } else {
            return localization[LocalizationKeys.NetworkNotification.Recovering.description]
        }
    }

    private func retriesExhaustedMessage(for snapshot: ConnectivitySnapshot) -> String {
        if let retries = snapshot.retryAttempt {
            return localization.getString(
                LocalizationKeys.NetworkNotification.RetriesExhausted.withCount,
                retries
            )
        } else {
            return localization[LocalizationKeys.NetworkNotification.RetriesExhausted.description]
        }
    }

    private func startCountdown(duration: TimeInterval) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        retryCountdown = Int(duration)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                self.retryCountdown -= 1

                if self.retryCountdown <= 0 {
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                    self.retryCountdown = 0
                }

                self.refreshLocalization()
            }
        }
    }

    nonisolated private func stopTimers() {
        Task { @MainActor in
            countdownTimer?.invalidate()
            countdownTimer = nil
            retryCountdown = 0
            autoRetryTimer?.invalidate()
            autoRetryTimer = nil
        }
    }

    nonisolated private func stopAutoRetry() {
        Task { @MainActor in
            autoRetryTimer?.invalidate()
            autoRetryTimer = nil
        }
    }

    private func refreshLocalization() {
        if let snapshot = currentSnapshot {
            handle(snapshot)
        }
    }

    public func dismiss() {
        isVisible = false
        stopTimers()
    }

    public var retryButtonTitle: String {
        localization[LocalizationKeys.NetworkNotification.retryButton]
    }

    public var dismissButtonTitle: String {
        localization[LocalizationKeys.NetworkNotification.dismissButton]
    }

    private var cancellables = Set<AnyCancellable>()
}

public extension ConnectivityNotification {
    var shouldAutoHide: Bool {
        type == .success
    }

    var isCritical: Bool {
        type == .error && showRetryButton
    }

    var icon: String {
        switch type {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .recovering: return "arrow.clockwise.circle.fill"
        }
    }
}
