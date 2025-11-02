import Combine
import Foundation

public actor ConnectivityPublisher {

    nonisolated(unsafe) private let snapshotSubject: CurrentValueSubject<ConnectivitySnapshot, Never>
    private var currentSnapshot: ConnectivitySnapshot

    public nonisolated var snapshot: ConnectivitySnapshot {
        snapshotSubject.value
    }

    public nonisolated var connectivityStream: AnyPublisher<ConnectivitySnapshot, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    public init() {
        self.currentSnapshot = .initial
        self.snapshotSubject = CurrentValueSubject(.initial)
        Log.debug("[ConnectivityPublisher] Initialized with initial snapshot")
    }

    public func publish(_ intent: ConnectivityIntent) async {
        let correlation = intent.correlationId ?? UUID()

        var effectiveReason = intent.reason
        if effectiveReason == .none, let failure = intent.failure {
            effectiveReason = ConnectivityReason.from(networkFailure: failure)
        }

        if effectiveReason == .none {
            effectiveReason = .unknown
        }

        let nextSnapshot = ConnectivitySnapshot(
            status: intent.status,
            reason: effectiveReason,
            source: intent.source,
            failure: intent.failure,
            connectId: intent.connectId,
            retryAttempt: intent.retryAttempt,
            retryBackoff: intent.retryBackoff,
            correlationId: correlation,
            occurredAt: Date()
        )

        currentSnapshot = nextSnapshot
        snapshotSubject.send(nextSnapshot)
        logTransition(nextSnapshot)
    }

    private func logTransition(_ snapshot: ConnectivitySnapshot) {
        let statusEmoji = statusEmoji(for: snapshot.status)
        let sourceLabel = sourceLabel(for: snapshot.source)

        Log.debug("[CONNECTIVITY] [\(sourceLabel)] \(statusEmoji) \(snapshot.status) - \(snapshot.reason)")

        if let retryAttempt = snapshot.retryAttempt {
            Log.debug("    Retry: \(retryAttempt)")
        }

        if let backoff = snapshot.retryBackoff {
            Log.debug("    Backoff: \(String(format: "%.1fs", backoff))")
        }

        if let failure = snapshot.failure {
            Log.debug("    Failure: \(failure.localizedDescription)")
        }
    }

    private func statusEmoji(for status: ConnectivityStatus) -> String {
        switch status {
        case .connected:
            return "[OK]"
        case .connecting:
            return "[CONNECTING]"
        case .disconnected:
            return "[FAILED]"
        case .recovering:
            return "[RECOVERING]"
        case .unavailable:
            return "[UNAVAILABLE]"
        case .shuttingDown:
            return "[SHUTDOWN]"
        case .retriesExhausted:
            return "[EXHAUSTED]"
        }
    }

    private func sourceLabel(for source: ConnectivitySource) -> String {
        switch source {
        case .system:
            return "System"
        case .dataCenter:
            return "DataCenter"
        case .internetProbe:
            return "Internet"
        case .manualAction:
            return "Manual"
        }
    }
}

extension ConnectivityPublisher {

    public nonisolated func publishSync(_ intent: ConnectivityIntent) {
        Task {
            await publish(intent)
        }
    }
}
