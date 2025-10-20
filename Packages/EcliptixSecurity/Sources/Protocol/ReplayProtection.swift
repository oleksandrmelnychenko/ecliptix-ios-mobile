import Foundation
import EcliptixCore

// MARK: - Replay Protection
/// Protects against replay attacks by tracking processed nonces and message indices
/// Migrated from: Ecliptix.Protocol.System/Core/ReplayProtection.cs
public final class ReplayProtection {

    // MARK: - Properties
    private var processedNonces: [String: Date] = [:]
    private var messageWindows: [UInt64: MessageWindow] = [:]
    private let nonceLifetime: TimeInterval
    private var maxOutOfOrderWindow: UInt64
    private let baseWindow: UInt64
    private let maxWindow: UInt64
    private var recentMessageCount: Int = 0
    private var lastWindowAdjustment: Date = Date()
    private var cleanupTimer: Timer?
    private let lock = NSLock()
    private var isDisposed = false

    // MARK: - Initialization
    public init(
        nonceLifetime: TimeInterval = 300, // 5 minutes
        maxOutOfOrderWindow: UInt64 = 1000,
        maxWindow: UInt64 = 5000
    ) {
        self.nonceLifetime = nonceLifetime
        self.baseWindow = maxOutOfOrderWindow
        self.maxOutOfOrderWindow = maxOutOfOrderWindow
        self.maxWindow = maxWindow

        // Start cleanup timer (every 30 seconds)
        self.cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: 30.0,
            repeats: true
        ) { [weak self] _ in
            self?.cleanupExpiredEntries()
            self?.adjustWindowSize()
        }
    }

    deinit {
        dispose()
    }

    // MARK: - Check and Record Message
    /// Checks if a message has been seen before and records it
    /// Migrated from: CheckAndRecordMessage()
    public func checkAndRecordMessage(
        nonce: Data,
        messageIndex: UInt64,
        chainIndex: UInt64 = 0
    ) -> Result<Unit, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("ReplayProtection has been disposed"))
        }

        guard !nonce.isEmpty else {
            return .failure(.generic("Nonce cannot be null or empty"))
        }

        lock.lock()
        defer { lock.unlock() }

        // Check nonce
        let nonceKey = nonce.base64EncodedString()
        if processedNonces[nonceKey] != nil {
            return .failure(.generic("Replay attack detected: nonce already processed"))
        }

        // Check message window
        let windowCheck = checkMessageWindow(chainIndex: chainIndex, messageIndex: messageIndex)
        if case .failure(let error) = windowCheck {
            return .failure(error)
        }

        // Record
        processedNonces[nonceKey] = Date()
        updateMessageWindow(chainIndex: chainIndex, messageIndex: messageIndex)
        recentMessageCount += 1

        return .success(.value)
    }

    // MARK: - Check Message Window
    private func checkMessageWindow(chainIndex: UInt64, messageIndex: UInt64) -> Result<Unit, ProtocolFailure> {
        guard let window = messageWindows[chainIndex] else {
            messageWindows[chainIndex] = MessageWindow(initialIndex: messageIndex)
            return .success(.value)
        }

        if messageIndex <= window.highestProcessedIndex {
            if window.isProcessed(messageIndex) {
                return .failure(.generic("Replay attack detected: message index \(messageIndex) already processed for chain \(chainIndex)"))
            }

            let gap = window.highestProcessedIndex - messageIndex
            if gap > maxOutOfOrderWindow {
                return .failure(.generic("Message index \(messageIndex) is too far behind (gap: \(gap), max: \(maxOutOfOrderWindow))"))
            }
        }

        return .success(.value)
    }

    // MARK: - Update Message Window
    private func updateMessageWindow(chainIndex: UInt64, messageIndex: UInt64) {
        if let window = messageWindows[chainIndex] {
            window.markProcessed(messageIndex)
        } else {
            messageWindows[chainIndex] = MessageWindow(initialIndex: messageIndex)
        }
    }

    // MARK: - Cleanup Expired Entries
    private func cleanupExpiredEntries() {
        guard !isDisposed else { return }

        let cutoff = Date().addingTimeInterval(-nonceLifetime)

        lock.lock()
        defer { lock.unlock() }

        // Clean up old nonces
        let expiredKeys = processedNonces.filter { $0.value < cutoff }.map { $0.key }
        for key in expiredKeys {
            processedNonces.removeValue(forKey: key)
        }

        // Clean up old message windows
        for (_, window) in messageWindows {
            window.cleanupOldEntries(cutoff: cutoff)
        }
    }

    // MARK: - Adjust Window Size
    private func adjustWindowSize() {
        guard !isDisposed else { return }

        let now = Date()
        guard now.timeIntervalSince(lastWindowAdjustment) >= 30.0 else { return }

        lock.lock()
        defer { lock.unlock() }

        let messageRate = Double(recentMessageCount) / 2.0

        if messageRate > 50 {
            maxOutOfOrderWindow = min(baseWindow * 3, maxWindow)
        } else if messageRate > 20 {
            maxOutOfOrderWindow = min(baseWindow * 2, maxWindow)
        } else {
            maxOutOfOrderWindow = baseWindow
        }

        recentMessageCount = 0
        lastWindowAdjustment = now
    }

    // MARK: - On Ratchet Rotation
    /// Clears message windows when ratchet rotates
    public func onRatchetRotation() {
        guard !isDisposed else { return }

        lock.lock()
        defer { lock.unlock() }

        messageWindows.removeAll()
    }

    // MARK: - Dispose
    public func dispose() {
        guard !isDisposed else { return }

        isDisposed = true
        cleanupTimer?.invalidate()
        cleanupTimer = nil

        lock.lock()
        defer { lock.unlock() }

        processedNonces.removeAll()
        messageWindows.removeAll()
    }
}

// MARK: - Message Window
/// Tracks processed message indices within a chain
private final class MessageWindow {
    private var processedIndices: Set<UInt64> = []
    private let createdAt: Date = Date()
    var highestProcessedIndex: UInt64

    init(initialIndex: UInt64) {
        self.highestProcessedIndex = initialIndex
        self.processedIndices.insert(initialIndex)
    }

    func isProcessed(_ messageIndex: UInt64) -> Bool {
        return processedIndices.contains(messageIndex)
    }

    func markProcessed(_ messageIndex: UInt64) {
        processedIndices.insert(messageIndex)
        if messageIndex > highestProcessedIndex {
            highestProcessedIndex = messageIndex
        }
    }

    func cleanupOldEntries(cutoff: Date) {
        if createdAt < cutoff {
            let keepFromIndex = highestProcessedIndex > 1000 ? highestProcessedIndex - 1000 : 0
            processedIndices = processedIndices.filter { $0 >= keepFromIndex }
        }
    }
}
